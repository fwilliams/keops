
#include <stdio.h>
#include <iostream>
#include <assert.h>
#include <cuda.h>
#include <vector>

#include "Pack.h"

using namespace std;


template <typename T>
__device__ static constexpr T static_max_device(T a, T b) {
    return a < b ? b : a;
}

template <typename TYPE, int DIMVECT>
__global__ void reduce0(TYPE* in, TYPE* out, int sizeY,int nx) {
    /* Function used as a final reduction pass in the 2D scheme,
     * once the block reductions have been made.
     * Takes as input:
     * - in,  a  sizeY * (nx * DIMVECT ) array
     * - out, an          nx * DIMVECT   array
     *
     * Computes, in parallel, the "columnwise"-sum (which correspond to lines of blocks)
     * of *in and stores the result in out.
     */
    TYPE res = 0;
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if(tid < nx*DIMVECT) {
        for (int i = 0; i < sizeY; i++)
            res += in[tid + i*nx*DIMVECT]; // We use "+=" as a reduction op. But it could be anything, really!
        /*res = in[tid+ nx* DIMVECT];*/
        out[tid] = res;
    }
}








// thread kernel: computation of x1i = sum_j k(x2i,x3i,...,y1j,y2j,...) for index i given by thread id.
// N.B.: This routine by itself is generic, and does not specifically refer to the "sum" operation.
//       It can be used for any Map-Reduce operation, provided that "fun" is well-understood.
template < typename TYPE, class FUN, class PARAM >
__global__ void GpuConv2DOnDevice(FUN fun, PARAM param, int nx, int ny, TYPE** px, TYPE** py) {
    /*
     * px and py are pointers to the device global memory.
     * both are arrays of arrays with the relevant size: for instance,
     * px[1] is a TYPE array of size ( nx * DIMSX::VAL(1) ).
     *
     * (*px) = px[0] is the output array, of size (nx * DIMSX::FIRST).
     *
     */
    // gets dimensions and number of variables of inputs of function FUN
    typedef typename FUN::DIMSX DIMSX;  // DIMSX is a "vector" of templates giving dimensions of xi variables
    typedef typename FUN::DIMSY DIMSY;  // DIMSY is a "vector" of templates giving dimensions of yj variables
    const int DIMPARAM = FUN::DIMPARAM; // DIMPARAM is the total size of the param vector
    const int DIMX = DIMSX::SUM;        // DIMX  is sum of dimensions for xi variables
    const int DIMY = DIMSY::SUM;        // DIMY  is sum of dimensions for yj variables
    const int DIMX1 = DIMSX::FIRST;     // DIMX1 is dimension of output variable

    // Load the parameter vector in the Thread Memory, for improved efficiency
    //TYPE param_loc[static_max_device(DIMPARAM,1)];
    // (Jean :) Direct inlining to compile on Ubuntu 16.04 with nvcc7.5, 
    //          which is a standard config in research. For whatever reason, I can't make
    //          it work an other way... Is it bad practice/performance?
    TYPE param_loc[DIMPARAM < 1 ? 1 : DIMPARAM]; 
    
    for(int k=0; k<DIMPARAM; k++)
        param_loc[k] = param[k];

    // Weird syntax to create a pointer in shared memory.
    extern __shared__ char yj_char[];
    TYPE* const yj = reinterpret_cast<TYPE*>(yj_char);

    // Step 1 : Load in Thread Memory the information needed in the current line ---------------------------
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    TYPE xi[DIMX];
    TYPE tmp[DIMX1]; // (Jean :) Why do we use a temp. variable instead of accumulating the results
    //          in xi[0:DIMX1] ? It's not clear to me. Is it some kind of clever
    //          memory access optimization ?
    //          (b. :) Pas d'optimization ici, mais de la gestion de mémoire : xi[0:DIMX1] est memoire global et est 'commun à tous les thread'.
    //                  Imposible de faire += sur une variable global depuis chaque thread (il faut coder une opération de réduction). Et surtout, 
    //                  cela couterai un acces memoire globale à chaque incrémentation: sous optimal.
    //                  Ainsi, il faut d'abord accumuler dans register (ie localement) puis chaque thread écrit le résultat dans une case mémoire
   //                   differente (namely: '(*px)[blockIdx.y*DIMX1*nx+i*DIMX1+k]'). A la fin, on réduit en appelant reduced0.
    if(i<nx) { // we will compute x1i only if i is in the range
        for(int k=0; k<DIMX1; k++)
            tmp[k] = 0.0f; // initialize output
        // Load xi from device global memory.
        // Remember that we use an interleaved memory scheme where
        // xi = [ x1i, x2i, x3i, ... ].
        // Since we do not want to erase x1i, and only load x2i, x3i, etc.,
        // we add a small offset to the pointer given as an argument to the loading routine,
        // and ask it to only load "DIMSX::NEXT" bits of memory.
        load<DIMSX::NEXT>(i,xi+DIMX1,px+1); // load xi variables from global memory to local thread memory
    }

    // Step 2 : Load in Shared Memory the information needed in the current block of the product -----------
    // In the 1D scheme, we use a loop to run through the line.
    // In the 2D scheme presented here, the computation is done in parallel wrt both lines and columns.
    // Hence, we use "blockId.y" to get our current column number.
    int j = blockIdx.y * blockDim.x + threadIdx.x; // Same blockDim in x and y : squared tiles.
    if(j<ny) // we load yj from device global memory only if j<ny
        load<DIMSY>(j,yj+threadIdx.x*DIMY,py); // load yj variables from global memory to shared memory
    // More precisely : the j-th line of py is loaded to yj, at a location which depends on the
    // current threadId.

    __syncthreads(); // Make sure nobody lags behind

    // Step 3 : Once the data is loaded, execute fun --------------------------------------------------------
    // N.B.: There's no explicit summation here. Just calls to fun, which *accumulates* the results
    //       along the line, but does not *have* to use a "+=" as reduction operator.
    //       In the future, we could provide other reductions: max, min, ... whatever's needed.

    if(i<nx) { // we compute x1i only if needed
        TYPE* yjrel = yj; // Loop on the columns of the current block.
        for(int jrel = 0; (jrel<blockDim.x) && ((blockDim.x*blockIdx.y+jrel)< ny); jrel++, yjrel+=DIMY) {
            call<DIMSX,DIMSY>(fun,xi,yjrel,param_loc); // Call the function, which accumulates results in xi[0:DIMX1]
            for(int k=0; k<DIMX1; k++)
                tmp[k] += xi[k];
        }
        __syncthreads();  // Shouldn't we put the syncthreads outside the if ??? It may make no difference, mind.
    }

    // Step 4 : Save the result in global memory -----------------------------------------------------------
    // The current thread has computed the "linewise-sum" of a small block of the full Kernel Product
    // matrix, which corresponds to KP[ blockIdx.x * blockDim.x : (blockIdx.x+1) * blockDim.x ,
    //                                  blockIdx.y * blockDim.x : (blockIdx.y+1) * blockDim.x ]
    // We accumulate it in the output array (*px) = px[0], which has in fact gridSize.y * nx
    // lines of size DIMX1. The final reduction, which "sums over the block lines",
    // shall be done in a later step.
    if(i<nx)
        for(int k=0; k<DIMX1; k++)
            (*px)[blockIdx.y*DIMX1*nx+i*DIMX1+k] = tmp[k];
}
///////////////////////////////////////////////////


template < typename TYPE, class FUN, class PARAM >
int GpuConv2D_(FUN fun, PARAM param_h, int nx, int ny, TYPE** px_h, TYPE** py_h) {

    typedef typename FUN::DIMSX DIMSX;
    typedef typename FUN::DIMSY DIMSY;
    const int DIMPARAM = FUN::DIMPARAM;
    const int DIMX = DIMSX::SUM;
    const int DIMY = DIMSY::SUM;
    const int DIMX1 = DIMSX::FIRST;
    const int SIZEI = DIMSX::SIZE;
    const int SIZEJ = DIMSY::SIZE;

    // Data on the device. We need an "inflated" x1B, which contains gridSize.y "copies" of x_d
    // that will be reduced in the final pass.
    TYPE *x1B, *x_d, *y_d, *param_d;

    TYPE **px_d, **py_d;
    cudaHostAlloc((void**)&px_d, SIZEI*sizeof(TYPE*), cudaHostAllocMapped);
    cudaHostAlloc((void**)&py_d, SIZEJ*sizeof(TYPE*), cudaHostAllocMapped);

    // Allocate arrays on device.
    cudaMalloc((void**)&x_d, sizeof(TYPE)*(nx*DIMX));
    cudaMalloc((void**)&y_d, sizeof(TYPE)*(ny*DIMY));
    cudaMalloc((void**)&param_d, sizeof(TYPE)*(DIMPARAM));

    // Send data from host to device.

    cudaMemcpy(param_d, param_h, sizeof(TYPE)*DIMPARAM, cudaMemcpyHostToDevice);

    int nvals;
    px_d[0] = x_d;
    nvals = nx*DIMSX::VAL(0);
    for(int k=1; k<SIZEI; k++) {
        px_d[k] = px_d[k-1] + nvals;
        nvals = nx*DIMSX::VAL(k);
        cudaMemcpy(px_d[k], px_h[k], sizeof(TYPE)*nvals, cudaMemcpyHostToDevice);
    }
    py_d[0] = y_d;
    nvals = ny*DIMSY::VAL(0);
    cudaMemcpy(py_d[0], py_h[0], sizeof(TYPE)*nvals, cudaMemcpyHostToDevice);
    for(int k=1; k<SIZEJ; k++) {
        py_d[k] = py_d[k-1] + nvals;
        nvals = ny*DIMSY::VAL(k);
        cudaMemcpy(py_d[k], py_h[k], sizeof(TYPE)*nvals, cudaMemcpyHostToDevice);
    }

    // Compute on device.
    dim3 blockSize;
    blockSize.x = 192; // number of threads in each block
    int blockSizey = blockSize.x;
    dim3 gridSize;
    gridSize.x =  nx / blockSize.x + (nx%blockSize.x==0 ? 0 : 1);
    gridSize.y =  ny / blockSizey + (ny%blockSizey==0 ? 0 : 1);

    // Reduce  : grid and block are 1d
    dim3 blockSize2;
    blockSize2.x = 192; // number of threads in each block
    dim3 gridSize2;
    gridSize2.x =  (nx*DIMX1) / blockSize2.x + ((nx*DIMX1)%blockSize2.x==0 ? 0 : 1);

    cudaMalloc((void**)&x1B, sizeof(TYPE)*(nx*DIMX1*gridSize.y));
    px_d[0] = x1B;

    // Size of the SharedData : blockSize.x*(DIMY)*sizeof(TYPE)
    GpuConv2DOnDevice<TYPE><<<gridSize,blockSize,blockSize.x*(DIMY)*sizeof(TYPE)>>>(fun,param_d,nx,ny,px_d,py_d);

    // Since we've used a 2D scheme, there's still a "blockwise" line reduction to make on
    // the output array px_d[0] = x1B. We go from shape ( gridSize.y * nx, DIMX1 ) to (nx, DIMX1)
    reduce0<TYPE,DIMX1><<<gridSize2, blockSize2>>>(x1B, x_d, gridSize.y,nx);

    // block until the device has completed
    cudaThreadSynchronize();

    // Send data from device to host.
    cudaMemcpy(*px_h, x_d, sizeof(TYPE)*(nx*DIMX1),cudaMemcpyDeviceToHost);

    // Free memory.
    cudaFree(x_d);
    cudaFree(y_d);
    cudaFree(x1B);
    cudaFreeHost(px_d);
    cudaFreeHost(py_d);

    return 0;
}

// Wrapper around GpuConv2D, which takes lists of arrays *x1, *x2, ..., *y1, *y2, ...
// and use getlist to enroll them into "pointers arrays" px and py.
template < typename TYPE, class FUN, class PARAM, typename... Args >
int GpuConv2D(FUN fun, PARAM param, int nx, int ny, TYPE* x1_h, Args... args) {

    typedef typename FUN::VARSI VARSI;
    typedef typename FUN::VARSJ VARSJ;

    const int SIZEI = VARSI::SIZE+1;
    const int SIZEJ = VARSJ::SIZE;

    using DIMSX = GetDims<VARSI>;
    using DIMSY = GetDims<VARSJ>;

    using INDSI = GetInds<VARSI>;
    using INDSJ = GetInds<VARSJ>;

    TYPE *px_h[SIZEI];
    TYPE *py_h[SIZEJ];

    px_h[0] = x1_h;
    getlist<INDSI>(px_h+1,args...);
    getlist<INDSJ>(py_h,args...);

    return GpuConv2D_(fun,param,nx,ny,px_h,py_h);

}

// Idem, but with args given as an array of arrays, instead of an explicit list of arrays
template < typename TYPE, class FUN, class PARAM >
int GpuConv2D(FUN fun, PARAM param, int nx, int ny, TYPE* x1_h, TYPE** args) {
    typedef typename FUN::VARSI VARSI;
    typedef typename FUN::VARSJ VARSJ;

    const int SIZEI = VARSI::SIZE+1;
    const int SIZEJ = VARSJ::SIZE;

    using DIMSX = GetDims<VARSI>;
    using DIMSY = GetDims<VARSJ>;

    using INDSI = GetInds<VARSI>;
    using INDSJ = GetInds<VARSJ>;

    TYPE *px_h[SIZEI];
    TYPE *py_h[SIZEJ];

    px_h[0] = x1_h;
    for(int i=1; i<SIZEI; i++)
        px_h[i] = args[INDSI::VAL(i-1)];
    for(int i=0; i<SIZEJ; i++)
        py_h[i] = args[INDSJ::VAL(i)];

    return GpuConv2D_(fun,param,nx,ny,px_h,py_h);

}




// Host implementation of the convolution, for comparison


template < typename TYPE, class FUN, class PARAM >
int CpuConv_(FUN fun, PARAM param, int nx, int ny, TYPE** px, TYPE** py) {
    typedef typename FUN::DIMSX DIMSX;
    typedef typename FUN::DIMSY DIMSY;
    const int DIMX = DIMSX::SUM;
    const int DIMY = DIMSY::SUM;
    const int DIMX1 = DIMSX::FIRST;

    TYPE xi[DIMX], yj[DIMY], tmp[DIMX1];
    for(int i=0; i<nx; i++) {
        load<DIMSX>(i,xi,px);
        for(int k=0; k<DIMX1; k++)
            tmp[k] = 0;
        for(int j=0; j<ny; j++) {
            load<DIMSY>(j,yj,py);
            call<DIMSX,DIMSY>(fun,xi,yj,param);
            for(int k=0; k<DIMX1; k++)
                tmp[k] += xi[k];
        }
        for(int k=0; k<DIMX1; k++)
            px[0][i*DIMX1+k] = tmp[k];
    }

    return 0;
}

// Wrapper with an user-friendly input format for px and py.
template < typename TYPE, class FUN, class PARAM, typename... Args >
int CpuConv(FUN fun, PARAM param, int nx, int ny, TYPE* x1, Args... args) {
    typedef typename FUN::VARSI VARSI;
    typedef typename FUN::VARSJ VARSJ;

    const int SIZEI = VARSI::SIZE+1;
    const int SIZEJ = VARSJ::SIZE;

    using DIMSX = GetDims<VARSI>;
    using DIMSY = GetDims<VARSJ>;

    using INDSI = GetInds<VARSI>;
    using INDSJ = GetInds<VARSJ>;

    TYPE *px[SIZEI];
    TYPE *py[SIZEJ];

    px[0] = x1;
    getlist<INDSI>(px+1,args...);
    getlist<INDSJ>(py,args...);

    return CpuConv_(fun,param,nx,ny,px,py);
}

// Idem, but with args given as an array of arrays, instead of an explicit list of arrays.
template < typename TYPE, class FUN, class PARAM >
int CpuConv(FUN fun, PARAM param, int nx, int ny, TYPE* x1, TYPE** args) {
    typedef typename FUN::VARSI VARSI;
    typedef typename FUN::VARSJ VARSJ;

    const int SIZEI = VARSI::SIZE+1;
    const int SIZEJ = VARSJ::SIZE;

    using DIMSX = GetDims<VARSI>;
    using DIMSY = GetDims<VARSJ>;

    using INDSI = GetInds<VARSI>;
    using INDSJ = GetInds<VARSJ>;

    TYPE *px[SIZEI];
    TYPE *py[SIZEJ];

    px[0] = x1;
    for(int i=1; i<SIZEI; i++)
        px[i] = args[INDSI::VAL(i-1)];
    for(int i=0; i<SIZEJ; i++)
        py[i] = args[INDSJ::VAL(i)];

    return CpuConv_(fun,param,nx,ny,px,py);
}

// Generic function, created from a formula F (see autodiff.h), and a tag which is equal:
// - to 0 if you do the summation over j (with i the index of the output vector),
// - to 1 if you do the summation over i (with j the index of the output vector).
//
// (Jean :) It's a nice wrapper, but I don't really know why it's been put in this file ?
//          Wouldn't the beginning of "autodiff.h" be a more appropriate location ?
template < class F, int tagI=0 >
class Generic {

    static const int tagJ = 1-tagI;

  public :

    struct sEval { // static wrapper
        using VARSI = typename F::VARS<tagI>; // Use the tag to select the "parallel"  variable
        using VARSJ = typename F::VARS<tagJ>; // Use the tag to select the "summation" variable
        using DIMSX = typename GetDims<VARSI>::PUTLEFT<F::DIM>; // dimensions of "i" variables. We add the output's dimension.
        using DIMSY = GetDims<VARSJ>;                           // dimensions of "j" variables

        using INDSI = GetInds<VARSI>;
        using INDSJ = GetInds<VARSJ>;

        using INDS = ConcatPacks<INDSI,INDSJ>;  // indices of variables

        using tmp = typename F::VARS<2>;
        static const int DIMPARAM = tmp::SIZE;

        template < typename... Args >
        __host__ __device__ __forceinline__ void operator()(Args... args) {
            F::template Eval<INDS>(args...);
        }
    };

};


