// Import done by Cmake
// #include <torch/extension.h>
// #include <pybind11/pybind11.h>

#include "common/keops_io.h"
#include "binders/checks.h"

namespace keops_binders {

/////////////////////////////////////////////////////////////////////////////////
//                  Template specialization (aTen Tensors)                     //
/////////////////////////////////////////////////////////////////////////////////

//Specialization of functions in keops/binders/checks.h

template <>
int get_ndim(at::Tensor obj_ptri) {
  return obj_ptri.dim();
}

template <>
int get_size(at::Tensor obj_ptri, int l) {
  return obj_ptri.size(l);
}

template <>
__TYPE__ *get_data(at::Tensor obj_ptri) {
  return obj_ptri.data< __TYPE__ >();
}

template <>
bool is_contiguous(at::Tensor obj_ptri) {
  return obj_ptri.is_contiguous();
}

#if USE_DOUBLE
#define AT_TYPE at::kDouble
#else
#define AT_TYPE at::kFloat
#endif

template <>
at::Tensor allocate_result_array(int* shape_out, int nbatchdims) {
  // ATen only accepts "long int arrays" to specify the shape of a new tensor:
  int64_t shape_out_long[nbatchdims + 2];
  std::copy(shape_out, shape_out + nbatchdims + 2, shape_out_long);
  c10::ArrayRef < int64_t > shape_out_array(shape_out_long, (int64_t) nbatchdims + 2);

  return torch::empty(shape_out_array, at::device(at::kCPU).dtype(AT_TYPE).requires_grad(true));

}

#if USE_CUDA
template <>
at::Tensor allocate_result_array_gpu(int* shape_out, int nbatchdims) {
  // ATen only accepts "long int arrays" to specify the shape of a new tensor:
  int64_t shape_out_long[nbatchdims + 2];
  std::copy(shape_out, shape_out + nbatchdims + 2, shape_out_long);
  c10::ArrayRef < int64_t > shape_out_array(shape_out_long, (int64_t) nbatchdims + 2);

  return torch::empty(shape_out_array, at::device(at::kGPU).dtype(AT_TYPE).requires_grad(true));

}
#endif

template <>
__INDEX__ *get_rangedata(at::Tensor obj_ptri) {
  return obj_ptri.data< __INDEX__ >();
}


/////////////////////////////////////////////////////////////////////////////////
//                    PyBind11 entry point                                     //
/////////////////////////////////////////////////////////////////////////////////


// the following macro force the compiler to change MODULE_NAME to its value
#define VALUE_OF(x) x

#define xstr(s) str(s)
#define str(s) #s

PYBIND11_MODULE(VALUE_OF(MODULE_NAME), m) {
m.doc() = "keops for pytorch through pybind11"; // optional module docstring

m.def("genred_pytorch", &generic_red <at::Tensor, at::Tensor>, "Entry point to keops - pytorch version.");

m.attr("tagIJ") = TAGIJ;
m.attr("dimout") = DIMOUT;
m.attr("formula") = f;
m.attr("compiled_formula") = xstr(FORMULA_OBJ_STR);
m.attr("compiled_aliases") = xstr(VAR_ALIASES_STR);
}

}
