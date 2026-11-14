#!/usr/bin/env bash
# usage: ./build.sh [cpu|cuda|rocm]   (default cpu)
#
# cpu: plain Ubuntu, MPI and HDF5 only, no GPU toolkit or simulator
#
# the toolkits come from their vendors' own images: nvcc is not ours to redistribute
set -ex
CWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" && cd "$CWD"

FLAVOR=${1:-cpu}
case "${FLAVOR}" in
cpu)
    FROM_IMAGE="docker.io/library/ubuntu:26.04"
    VGPU_GPU=""
    ;;
cuda)
    FROM_IMAGE="docker.io/nvidia/cuda:13.5.0-devel-ubuntu26.04"
    VGPU_GPU="nvidia/h100"
    ;;
rocm)
    # not a -full image (8GB, more than a runner pulling it has free): the base one (1.2GB) and
    #  rocThrust + rocPRIM from its ROCm apt repository (run.sh). On 24.04: 26.04 has -full only
    FROM_IMAGE="docker.io/rocm/dev-ubuntu-24.04:7.2.4"
    VGPU_GPU="amd/mi300x"
    ;;
*)
    echo "unknown flavor '${FLAVOR}', expected cpu, cuda or rocm" >&2
    exit 1
    ;;
esac

IMAGE=${IMAGE:-"ghcr.io/0xz/hpc-containers"} # tagged :<flavor>
# cpu: no simulator, so no CMake toolchain file, and no GPU in the image description
CPU_ARGS=()
[[ "${FLAVOR}" != cpu ]] || CPU_ARGS=(--build-arg CMAKE_TOOLCHAIN= --build-arg "GPU_DESCRIPTION=no GPU")
docker build \
    --build-arg FROM_IMAGE="${FROM_IMAGE}" \
    --build-arg FLAVOR="${FLAVOR}" \
    --build-arg VGPU_GPU="${VGPU_GPU}" \
    "${CPU_ARGS[@]}" \
    ${MARCH:+--build-arg MARCH="${MARCH}"} \
    -t "${IMAGE}:${FLAVOR}" .
