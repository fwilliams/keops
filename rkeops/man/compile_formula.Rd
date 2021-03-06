% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/generic-compile_formula.R
\name{compile_formula}
\alias{compile_formula}
\title{Compile a formula defining a new operator}
\usage{
compile_formula(formula, var_aliases, dllname)
}
\arguments{
\item{formula}{text string, formula defining the new operator.}

\item{var_aliases}{text string, formated formula input arguments returned by
\code{\link[=format_var_aliases]{format_var_aliases()}} (specifically \verb{$var_aliases}).}

\item{dllname}{text string, the name associated to the related shared object
file.}
}
\value{
0 if no problem
}
\description{
User-defined operators associated to a formula are compiled in shared object
files with this function.
}
\details{
The function \code{compile_formula} sets up the working directory and the
environment to call the function \code{\link[=compile_code]{compile_code()}} for the
cmake compilation.

Afterwards, it also verify that the compilation went smoothly.
}
\seealso{
\code{\link[=keops_kernel]{keops_kernel()}}, \code{\link[=compile_code]{compile_code()}}
}
\author{
Ghislain Durif
}
\keyword{internal}
