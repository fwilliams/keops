#include <iostream>
#include <tuple>
#include <array>


constexpr std::size_t operator "" _z ( unsigned long long n )
    { return n; }

# define Ind(...) std::index_sequence<__VA_ARGS__>

// TensorDot(A,B,Ind(2,2,2), Ind(2,2), Ind(0,1), Ind(0,1))
// TensorDot(A,B,{2,2,2}, {2,2}, {0,1}, {0,1))

using DimFa  = Ind(2,2,2);
using DimFb  = Ind(2,2);
using ContFa = Ind(2);
using ContFb = Ind(0);

template<size_t... Is, size_t... is>
static constexpr size_t get_columnmajor(std::index_sequence<is...>);

template<>
constexpr size_t get_columnmajor(std::index_sequence<>) {
    return 0_z;
}

template <size_t I, size_t... Is, size_t i, size_t... is>
static constexpr size_t get_columnmajor(std::index_sequence<i, is...>) {
    static_assert(i < I );
    return i + I * get_columnmajor<Is...>(std::index_sequence<is...>());
    return 0_z;
}


template< size_t ... DIMFA, size_t ... DIMFB, size_t ... CONTFA, size_t ... CONTFB >
static constexpr std::tuple<std::array< size_t, sizeof...(DIMFA)> ,
                            std::array< size_t, sizeof...(DIMFB)> ,
                            std::array< size_t, sizeof...(DIMFA)-sizeof...(CONTFA)>,
                            std::array< size_t, sizeof...(DIMFB)-sizeof...(CONTFB)>,
                            std::array< size_t, sizeof...(DIMFA) + sizeof...(DIMFB)- sizeof...(CONTFA) - sizeof...(CONTFB)>,
                            std::array< size_t, sizeof...(DIMFA) + sizeof...(DIMFB)- sizeof...(CONTFA)                    > > build_array4( std::index_sequence<DIMFA... >,
                                                                                  std::index_sequence<DIMFB... >,
                                                                                  std::index_sequence<CONTFA...>,
                                                                                  std::index_sequence<CONTFB...> 
                                                                                 ) noexcept {
                                                           
   // Cast index_sequence to array
   auto dimfa  = std::array<size_t, sizeof...(DIMFA ) > { DIMFA... };
   auto dimfb  = std::array<size_t, sizeof...(DIMFB ) > { DIMFB... };
   auto contfa = std::array<size_t, sizeof...(CONTFA) > { CONTFA... };
   auto contfb = std::array<size_t, sizeof...(CONTFB) > { CONTFB... };

   // get size of the contraction
   constexpr size_t number_of_dim_a = dimfa.size() - contfa.size() ;
   constexpr size_t number_of_dim_b = dimfb.size() - contfb.size() ;

   std::array<size_t, number_of_dim_b + number_of_dim_a> dim_keep{};
   std::array<size_t, number_of_dim_a> dim_keep_a{};
   std::array<size_t, number_of_dim_b> dim_keep_b{};

   for(auto i=0; i < number_of_dim_a; i++) {
        dim_keep_a[i]= dimfa[i];
        dim_keep[i] = dimfa[i];
   }

   for(auto i=0; i < number_of_dim_b; i++) {
        dim_keep_b[i]= dimfb[contfb.size() + i];
        dim_keep[i+ number_of_dim_a] = dim_keep_b[i];
   }
                                                              
   std::array<size_t, contfa.size()> dim_sum{};
   for(auto i=0; i < contfa.size(); i++) {
        dim_sum[i]= dimfa[number_of_dim_a + i];
   }
   

   std::array<size_t, contfa.size() + dim_keep.size()> dim_tot{};
   for(auto i=0; i < dim_keep.size(); i++) {
        dim_tot[i]= dim_keep[i];
   }
   for(auto i=0; i < contfa.size(); i++) {
        dim_tot[dim_keep.size() + i]= dim_sum[i];
   }

   return std::make_tuple(dimfa, dimfb, 
                          dim_keep_a, dim_keep_b, dim_keep,
                          dim_tot) ;
}

template <size_t shape_index, size_t shape_size>
struct Looper {
    template <typename Functor>
    void operator()(const std::array<size_t, shape_size>& shape, Functor functor) {
        for (size_t index = 0; index < shape[shape_index]; ++index) {
            Looper<shape_index + 1, shape_size>() (
                    shape,
                    [index, &functor](auto... tail){ functor(std::forward_as_tuple(index, tail...)); }
                    );
        }
    }
};

template <size_t shape_size>
struct Looper<shape_size, shape_size> {
    template <typename Functor>
    void operator()(const std::array<size_t, shape_size>&, Functor functor) {
        functor();
    }
};

template <size_t shape_size, typename Functor>
void loop(const std::array<size_t, shape_size>& shape, Functor functor)
{
    Looper<0, shape_size>()(shape, functor);
}

//constexpr unsigned cilog2(unsigned val) { return val ? 1 + cilog2(val >> 1) : -1; }

template <size_t size1, size_t size2>
constexpr std::tuple<size_t,size_t,size_t> kd(std::array<size_t, size1> dim_a, std::array<size_t, size2> dim_b, size_t i, size_t j , size_t k) {
    size_t kda = dim_a[1]*dim_a[2]*i + dim_a[2]*j;
    size_t kdb = k;
    size_t I   = kda + kdb;
    return std::make_tuple(I,kda,kdb);
}

template <size_t NumberOfKeepDim>
constexpr size_t dimout(std::array<size_t, NumberOfKeepDim> keep_dim){
    size_t out = 1;  
    for(size_t i : keep_dim)
      out *= i;

    return out;
}

//template< size_t ... A>
//static constexpr std::array< size_t, sizeof...(A)> toArray( std::index_sequence<A... >) noexcept {
    //return std::array<size_t, sizeof...(A ) > { A... };
//}



int main() {

    double FA[8] = {4.4,5.4,6.2,6.5,7.5,6.1,8.7,1.3};
    double FB[4] = {1.4,1.2,1.5,1.22};

    // generate tuple (at compile time)
    constexpr auto ma4 = build_array4( DimFa(),
                                       DimFb(),
                                       ContFa(),
                                       ContFb() );
     
     
 
    // constexpr size_t sum_dim_a = 2;
    // constexpr size_t keep_dim_a[2] = [0,1];

    // constexpr size_t sum_dim_b[1] = 0;
    // constexpr size_t keep_dim_b[1] = [1];

    // print (at runtime)
    
    constexpr size_t dimout_var = dimout(std::get<4>(ma4)) ;
    double out[dimout_var];
    std::fill(out, out + dimout_var, 0);
   
    loop(std::get<5>(ma4),[&out,&FA,&FB,&ma4](std::tuple<size_t,size_t,size_t,size_t> it){
        const auto& dim_a = std::get<0>(ma4);
        const auto& dim_b = std::get<1>(ma4);

        std::tuple KD = kd(dim_a,dim_b,std::get<0>(it),std::get<1>(it),std::get<2>(it));
        size_t I   = std::get<0>(KD);
        size_t kda = std::get<1>(KD);
        size_t kdb = std::get<2>(KD);
        out[I] += FA[kda + std::get<3>(it)] * FB[dim_b[1]*std::get<3>(it) + kdb];
    });
 
    // -------------------------------------------------------------------------------------------------------------------------------------
    double out2[2*2*2] = {0,0,0,0,0,0,0,0};

    for(size_t i=0; i<2; i++)
        for(size_t j=0; j<2; j++)
         for(size_t k=0; k<2; k++)
            for(size_t l=0; l< 2; l++) {
            out2[4*i + 2*j + k] += FA[ 4*i + 2*j + l] * FB[ l*2 + k];
        }


   for (auto i=0; i< 8; i++) {
       std::cout << "out  = " << out[i]  << std::endl;
   }
   
   for (auto i=0; i< 8; i++) {
      std::cout << "out2 = " << out2[i]  << std::endl;
   }
   
   }