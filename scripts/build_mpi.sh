#!/usr/bin/env bash
# usage: build_mpi.sh <host|cuda|rocm>
#
# builds pmix -> ucx -> openmpi into one prefix
#
# env:
#   INSTALL_DIR  install prefix              (default /opt/mpi)
#   WORK_DIR     downloads + build trees     (default $PWD)
#   MARCH        -march value                (default x86-64-v3, "native" only for local use)
#   NPROC, MPI_VER, UCX_VER, PMIX_VER, CUDA_ROOT, ROCM_ROOT
set -ex

FLAVOR=${1:-${FLAVOR:-}}
NPROC=${NPROC:-$(nproc --all)}
MARCH=${MARCH:-x86-64-v3}
MPI_VER=${MPI_VER:-"5.0.11"} # bundles pmix v5.0.11 + prrte v3.0.14
UCX_GIT="https://github.com/openucx/ucx"
UCX_VER=${UCX_VER:-"v1.22.0"}
PMIX_GIT="https://github.com/openpmix/openpmix"
PMIX_VER=${PMIX_VER:-"v5.0.11"} # match the version bundled in ompi

FLAGS="-DNDEBUG -g0 -O3 -march=${MARCH}"

UCX_EXTRA=()
OMPI_EXTRA=()
case "${FLAVOR}" in
host) ;;
cuda)
    CUDA_ROOT=${CUDA_ROOT:-"/usr/local/cuda"}
    UCX_EXTRA=(--with-cuda="${CUDA_ROOT}")
    # no driver in the image: link libcuda from the stubs, the simulator provides it at runtime
    OMPI_EXTRA=(--with-cuda="${CUDA_ROOT}" --with-cuda-libdir="${CUDA_ROOT}/lib64/stubs")
    ;;
rocm)
    ROCM_ROOT=${ROCM_ROOT:-"/opt/rocm"}
    UCX_EXTRA=(--with-rocm="${ROCM_ROOT}")
    OMPI_EXTRA=(--with-rocm="${ROCM_ROOT}")
    ;;
*)
    echo "unknown flavor '${FLAVOR}', expected host, cuda or rocm" >&2
    exit 1
    ;;
esac

INSTALL_DIR=${INSTALL_DIR:-"/opt/mpi"}
WORK_DIR=$(mkdir -p "${WORK_DIR:-$PWD}" && cd "${WORK_DIR:-$PWD}" && pwd)
BUILD_DIR="${WORK_DIR}/build-${FLAVOR}"
LOG="${WORK_DIR}/.${FLAVOR}"

PMIX_SRC="${WORK_DIR}/pmix-${PMIX_VER}"
UCX_SRC="${WORK_DIR}/ucx-${UCX_VER}"
OMPI_SRC="${WORK_DIR}/openmpi-${MPI_VER}"

[[ -d "${PMIX_SRC}" ]] || git clone "${PMIX_GIT}" -b "${PMIX_VER}" --depth 10 --recursive --shallow-submodules "${PMIX_SRC}"
[[ -d "${UCX_SRC}" ]] || git clone "${UCX_GIT}" -b "${UCX_VER}" --depth 10 --recursive --shallow-submodules "${UCX_SRC}"

# use the release tarball (make dist), not a github tag archive: it ships the generated
# configure, the bundled pmix/prrte submodules and prebuilt docs (hence --disable-sphinx)
if [[ ! -d "${OMPI_SRC}" ]]; then
    TARBALL="${WORK_DIR}/openmpi-${MPI_VER}.tar.bz2"
    [[ -f "${TARBALL}" ]] || wget -qO "${TARBALL}" "https://download.open-mpi.org/release/open-mpi/v${MPI_VER%.*}/openmpi-${MPI_VER}.tar.bz2"
    tar xf "${TARBALL}" -C "${WORK_DIR}"
fi

[[ -f "${PMIX_SRC}/configure" ]] || (cd "${PMIX_SRC}" && ./autogen.pl)
[[ -f "${UCX_SRC}/configure" ]] || (cd "${UCX_SRC}" && ./autogen.sh)

rm -rf "${BUILD_DIR}" && mkdir -p "${BUILD_DIR}"/{pmix,ucx,ompi}

(
    cd "${BUILD_DIR}/pmix"
    "${PMIX_SRC}/configure" CFLAGS="${FLAGS}" CXXFLAGS="${FLAGS}" --prefix="${INSTALL_DIR}"
    make -j "$NPROC" && make install
) 1> >(tee "${LOG}.pmix.out") 2> >(tee "${LOG}.pmix.err" >&2)

# --enable-mt: thread safe workers, for MPI_THREAD_MULTIPLE (else Open MPI does not select UCX
#  then, e.g. for HDF5's subfiling); lower thread levels keep UCX's single threaded workers
# ucx hardcodes -Werror; gcc 13 emits a false positive maybe-uninitialized in ucs/arch/bitops.h
# at -O3, our flags come after ucx's own so this downgrades it to a warning
UCX_FLAGS="${FLAGS} -Wno-error=maybe-uninitialized"
(
    cd "${BUILD_DIR}/ucx"
    "${UCX_SRC}/configure" CFLAGS="${UCX_FLAGS}" CXXFLAGS="${UCX_FLAGS}" --prefix="${INSTALL_DIR}" \
        --without-knem --enable-mt "${UCX_EXTRA[@]}"
    make -j "$NPROC" && make install
) 1> >(tee "${LOG}.ucx.out") 2> >(tee "${LOG}.ucx.err" >&2)

(
    cd "${BUILD_DIR}/ompi"
    "${OMPI_SRC}/configure" CFLAGS="${FLAGS}" CXXFLAGS="${FLAGS}" --prefix="${INSTALL_DIR}" \
        --with-pmix="${INSTALL_DIR}" --with-ucx="${INSTALL_DIR}" --disable-sphinx "${OMPI_EXTRA[@]}"
    make -j "$NPROC" && make install
) 1> >(tee "${LOG}.ompi.out") 2> >(tee "${LOG}.ompi.err" >&2)

case "${FLAVOR}" in
cuda) "${INSTALL_DIR}/bin/ompi_info" --parsable --all | grep mpi_built_with_cuda_support:value:true ;;
rocm) "${INSTALL_DIR}/bin/ompi_info" | grep -i "MCA accelerator: rocm" ;;
*) "${INSTALL_DIR}/bin/ompi_info" | grep "Open MPI:" ;;
esac
