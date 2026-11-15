#!/usr/bin/env bash
# usage: test/run.sh <cpu|cuda|rocm>   (inside the image)
#
#   host:   MPI ring + allreduce, parallel HDF5 through MPI-IO and subfiling
#   device: GPU-aware MPI, device pointers straight to MPI_Send/Recv, on the simulated GPU
#
# env: TESTS=host|device|all (default all; cpu: host only), WORK_DIR (default a temp dir)
set -ex
CWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FLAVOR=${1:-${FLAVOR:-}}
FLAVOR=${FLAVOR/cuda12/cuda} # the same tests as cuda's
TESTS=${TESTS:-all}
[[ "${FLAVOR}" != cpu ]] || TESTS=host
MPI=${MPI_HOME:-/opt/mpi}
HDF5=${HDF5_ROOT:-/opt/hdf5}
WORK_DIR=${WORK_DIR:-$(mktemp -d)}
cd "${WORK_DIR}"

"${MPI}/bin/ompi_info" | grep -iE "Open MPI:|MCA (accelerator|pml|btl): "

if [[ "${TESTS}" == host || "${TESTS}" == all ]]; then
    "${MPI}/bin/mpicc" -O2 -o mpi_hello "${CWD}/mpi_hello.c"
    "${MPI}/bin/mpirun" -n 2 ./mpi_hello

    "${MPI}/bin/mpicc" -O2 -o hdf5_parallel "${CWD}/hdf5_parallel.c" \
        -I"${HDF5}/include" -L"${HDF5}/lib" -Wl,-rpath="${HDF5}/lib" -lhdf5
    "${MPI}/bin/mpirun" -n 2 ./hdf5_parallel
fi

if [[ "${TESTS}" == device || "${TESTS}" == all ]]; then
    MPI_FLAGS=(-I"${MPI}/include" -L"${MPI}/lib" -lmpi)
    case "${FLAVOR}" in
    # the simulator's nvcc (first on PATH) links the shared cudart, which it stands in for
    cuda) nvcc -O2 -x cu -o mpi_device "${CWD}/mpi_device.cpp" "${MPI_FLAGS[@]}" \
        -Xlinker -rpath -Xlinker "${MPI}/lib" ;;
    rocm) hipcc -O2 -x hip --offload-arch="${OFFLOAD_ARCH:-gfx942}" -o mpi_device \
        "${CWD}/mpi_device.cpp" "${MPI_FLAGS[@]}" -Wl,-rpath="${MPI}/lib" ;;
    *)
        echo "unknown flavor '${FLAVOR}', expected cuda or rocm" >&2
        exit 1
        ;;
    esac
    vgpu run "${MPI}/bin/mpirun" -n 2 ./mpi_device
fi
