COMP	   = gnu

DIM        = 1

USE_MPI    = TRUE
DEBUG      = FALSE

PROFILE    = FALSE

USE_RAD = TRUE
USE_NEUTRINO = FALSE

CASTRO_HOME = ../../..

EOS_DIR     := gamma_law

NETWORK_DIR := general_null
NETWORK_INPUTS := gammalaw.net

Opacity_dir := null

# number of radiation groups -  this needs to correspond to radiation.nGroups in
# the inputs file
NGROUPS := 64

Bpack   := ./Make.package
Blocs   := .

include $(CASTRO_HOME)/Exec/Make.Castro
