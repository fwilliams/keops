import numpy as np
from pykeops import default_cuda_type
from pykeops.common.keops_io import load_keops
from pykeops.common.get_options import get_tag_backend
from pykeops.common.parse_type import get_sizes, complete_aliases
from pykeops.common.utils import axis2cat


class Genred:
    def __init__(self, formula, aliases, reduction_op='Sum', axis=0, cuda_type=default_cuda_type, opt_arg=None):
        if opt_arg:
            self.formula = reduction_op + 'Reduction(' + formula + ',' + str(opt_arg) + ',' + str(axis2cat(axis)) + ')'
        else:
            self.formula = reduction_op + 'Reduction(' + formula + ',' + str(axis2cat(axis)) + ')'
        self.reduction_op = reduction_op
        self.aliases = complete_aliases(formula, aliases)
        self.cuda_type = cuda_type
        self.myconv = load_keops(self.formula,  self.aliases,  self.cuda_type, 'numpy')

    def __call__(self, *args, backend='auto', device_id=-1, ranges=None):
        # Get tags
        tagCpuGpu, tag1D2D, _ = get_tag_backend(backend, args)
        nx, ny = get_sizes(self.aliases, *args)
        if ranges is None : ranges = () # To keep the same type
        result = self.myconv.genred_numpy(nx, ny, tagCpuGpu, tag1D2D, 0, device_id, ranges, *args) 
        
        if self.reduction_op == "LogSumExp" : 
            # KeOps core returns pairs of floats (M,S), such that the result
            # is equal to  M+log(S)...
            # Users shouldn't have to bother with that!
            return (result[:,0] + np.log(result[:,1]) )[:,None]
        else :
            return result
