#------------------------------------------------------------------------------------#
#------------------------------FIND CUDA AND GPUs------------------------------------#
#------------------------------------------------------------------------------------#

# As of now, we use an ugly mix of old and new cmake method to properly detect cuda, nvcc and the gpu arch...
find_package(CUDA)

if(NOT DEFINED USE_CUDA)
    Set(USE_CUDA ${CUDA_FOUND})
endif()


if(CUDA_FOUND AND USE_CUDA)
   
   set(CMAKE_CUDA_COMPILER ${CUDA_NVCC_EXECUTABLE})
   enable_language(CUDA)

   # Options for nvcc
   CUDA_SELECT_NVCC_ARCH_FLAGS(out_variable "Auto")
   
   set (CUDA_PROPAGATE_HOST_FLAGS ON)
   
   List(APPEND CUDA_NVCC_FLAGS ${out_variable})
   List(APPEND CUDA_NVCC_FLAGS "--use_fast_math")
   List(APPEND CUDA_NVCC_FLAGS "--compiler-options=-fPIC")
   List(APPEND CUDA_NVCC_FLAGS "-ccbin ${CMAKE_CUDA_HOST_COMPILER}")
   
else()
    set(USE_CUDA 0)
endif()

# this flag is used in pragma
if(USE_CUDA)
    add_definitions(-DUSE_CUDA=1)
else()
    add_definitions(-DUSE_CUDA=0)
endif()
