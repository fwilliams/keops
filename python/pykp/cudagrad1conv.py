import numpy as np
import ctypes
from ctypes import *
import os.path

#nvcc -D "USE_DOUBLE_PRECISION=OFF" -D "CUDA_BLOCK_SIZE=192"  -Xcompiler -fPIC -shared -o cuda_conv.so cuda_conv.cu

# extract cuda_grad1conv function pointer in the shared object cuda_grad1conv.so
def get_cuda_grad1convs():
	"""
	Loads the gradient of the convolution routine from the compiled .so file.
	"""
	dll_name = 'cuda_grad1conv.so'
	dllabspath = os.path.dirname(os.path.abspath(__file__)) + os.path.sep+ 'build' + os.path.sep + dll_name
	dll = ctypes.CDLL(dllabspath, mode=ctypes.RTLD_GLOBAL)
	
	func_dict = {}
	for (name, routine) in [("gaussian",  dll.GaussGpuGrad1Conv), 
	                        ("laplacian", dll.LaplaceGpuGrad1Conv), 
	                        ("energy",    dll.EnergyGpuGrad1Conv) ] :
		func = routine
		# Arguments :          1/s^2,
		func.argtypes = [     c_float, 
		#                      alpha,              x,                y,              beta,             result,
						 POINTER(c_float), POINTER(c_float), POINTER(c_float), POINTER(c_float), POINTER(c_float), 
		#                 dim-xy,  dim-beta,   nx,    ny
						  c_int,    c_int,   c_int, c_int  ]
		func_dict[name] = routine
	return func_dict

# create __cuda_grad1conv function with get_cuda_grad1conv()
__cuda_grad1convs = get_cuda_grad1convs()

# convenient python wrapper for __cuda_grad1conv it does all job with types convertation from python ones to C++ ones 
def cuda_grad1conv(alpha,x, y, beta, result, sigma, kernel = "gaussian"):
	"""
	Implements the operation :
	
	(alpha_i, x_i, y_j, beta_j)  ->  (\partial_{x_i} < alpha_i | ( \sum_j k(x_i,y_j) beta_j )_i >)_i ,
	
	where k is a kernel function of parameter "sigma".
	Unlike a naive pytorch implementation, this code won't store in memory the matrix
	k(x_i,y_j) : it is therefore possible to use it when len(x) and len(y) are both large
	without getting a "memory overflow".
	
	N.B.: in an LDDMM setting, one would typically use "x = y = q", "beta = p". 
	"""
	# From python to C float pointers and int :
	alpha_p  =  alpha.ctypes.data_as(POINTER(c_float))
	x_p      =      x.ctypes.data_as(POINTER(c_float))
	y_p      =      y.ctypes.data_as(POINTER(c_float))
	beta_p   =   beta.ctypes.data_as(POINTER(c_float))
	result_p = result.ctypes.data_as(POINTER(c_float))
	
	nx = x.shape[0] ; ny = y.shape[0]
	
	dimPoint = x.shape[1]
	dimVect = beta.shape[1]
	
	ooSigma2 = float(1/ (sigma*sigma))  # Compute this once and for all
	
	# Let's use our GPU, which works "in place" :
	__cuda_grad1convs[kernel](ooSigma2, alpha_p, x_p, y_p, beta_p, result_p, dimPoint, dimVect, nx, ny )

# testing, benchmark grad1convolution with a naive python implementation of the Gaussian convolution
if __name__ == '__main__':
	
	np.set_printoptions(linewidth=200)
	sizeX    = int(600)
	sizeY    = int(100)
	dimPoint = int(3)
	dimVect  = int(3)
	sigma    = float(2)
	
	alpha = np.random.rand(sizeX,dimVect ).astype('float32')
	x     = np.random.rand(sizeX,dimPoint).astype('float32')
	y     = np.random.rand(sizeY,dimPoint).astype('float32')
	beta  = np.random.rand(sizeY,dimVect ).astype('float32')
	
	# Call cuda kernel
	gamma = np.zeros(dimPoint*sizeX).astype('float32')
	cuda_grad1conv(alpha,x, y, beta, gamma, sigma) # In place, gamma_i = k(x_i,y_j) @ beta_j
	gamma = gamma.reshape((sizeX,dimPoint))
	
	# A first implementation
	oosigma2 = 1 / (sigma * sigma) 
	gamma_py = np.zeros((sizeX,dimPoint)).astype('float32')
	
	for i in range(sizeX):
		for j in range(sizeY):
			rijk = (x[i,] - y[j,])
			rij2 = (rijk **2).sum()
			sga = (beta[j,] * alpha[i,]).sum()
			gamma_py[i,] -=  rijk * np.exp(-rij2 * oosigma2) * sga * 2.0 * oosigma2
			
	# compare output
	print("\nCuda convolution :")
	print(gamma)
	
	print("\nPython gradconvolution 1 :")
	print(gamma_py)
	
	print("\nIs everything okay ? ")
	print(np.allclose(gamma, gamma_py, atol = 1e-6))
