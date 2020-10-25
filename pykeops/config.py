import os
import importlib.util

from pykeops.common.gpu_utils import get_gpu_number
###############################################################
# Initialize some variables: the values may be redefined later

##########################################################
# Update config module: Search for GPU

gpu_available = get_gpu_number() > 0

numpy_found = importlib.util.find_spec('numpy') is not None
torch_found = importlib.util.find_spec('torch') is not None

###############################################################
# Compilation options

script_folder = os.path.dirname(os.path.abspath(__file__))

bin_folder = ""  # init bin_folder... shlould be populated with the set_bin_folder() function

# Set the verbosity option: display output of compilations. This is a boolean: False or True
verbose = bool(int(os.environ['PYKEOPS_VERBOSE'])) if 'PYKEOPS_VERBOSE' in os.environ else False

# Force compiled and set the cmake build type. This is a string with possible value "Release" or "Debug"
build_type = str(os.environ['PYKEOPS_BUILD_TYPE']) if ('PYKEOPS_BUILD_TYPE' in os.environ) else 'Release'
