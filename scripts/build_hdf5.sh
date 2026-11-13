#!/usr/bin/env bash
# usage: build_hdf5.sh
#
# parallel HDF5 with the subfiling VFD and Fortran, built with the MPI in $MPI
#
# env:
#   MPI          mpi prefix to build against (default /opt/mpi)
#   INSTALL_DIR  install prefix              (default /opt/hdf5)
#   WORK_DIR     source + build tree         (default $PWD)
#   MARCH        -march value                (default x86-64-v3)
#   HDF5_VER     git tag/branch, set empty for the default branch
#   NPROC        parallel build jobs         (default: all cores)
set -ex

NPROC=${NPROC:-$(nproc --all)}
MARCH=${MARCH:-x86-64-v3}
HDF5_GIT="https://github.com/HDFGroup/hdf5"
HDF5_VER=${HDF5_VER-"2.2.0"}
FLAGS="-DNDEBUG -g0 -O3 -march=${MARCH}"

MPI=${MPI:-"/opt/mpi"}
INSTALL_DIR=${INSTALL_DIR:-"/opt/hdf5"}
WORK_DIR=$(mkdir -p "${WORK_DIR:-$PWD}" && cd "${WORK_DIR:-$PWD}" && pwd)
BUILD_DIR="${WORK_DIR}/build-hdf5"
HDF5_SRC="${WORK_DIR}/hdf5-${HDF5_VER:-develop}"

if [[ ! -d "${HDF5_SRC}" ]]; then
    git clone "${HDF5_GIT}" ${HDF5_VER:+-b "${HDF5_VER}"} --depth 5 --recursive --shallow-submodules "${HDF5_SRC}"
fi

(
    rm -rf "${BUILD_DIR}" && mkdir -p "${BUILD_DIR}" && cd "${BUILD_DIR}"
    export CC="${MPI}/bin/mpicc" CXX="${MPI}/bin/mpicxx" FC="${MPI}/bin/mpif90"
    cmake -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
        -DCMAKE_C_FLAGS="${FLAGS}" \
        -DCMAKE_CXX_FLAGS="${FLAGS}" \
        -DCMAKE_Fortran_FLAGS="${FLAGS}" \
        -DMPI_C_LIBRARY="${MPI}/lib/libmpi.so" \
        -DMPIEXEC_EXECUTABLE="${MPI}/bin/mpiexec" \
        -DHDF5_ENABLE_PARALLEL=ON \
        -DHDF5_ENABLE_SUBFILING_VFD=ON \
        -DHDF5_BUILD_FORTRAN=ON \
        -DBUILD_TESTING=OFF \
        "${HDF5_SRC}"
    ninja -j "${NPROC}" && ninja install
) 1> >(tee "${WORK_DIR}/.hdf5.out") 2> >(tee "${WORK_DIR}/.hdf5.err" >&2)
