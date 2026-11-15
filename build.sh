#!/usr/bin/env bash
# usage: ./build.sh [cpu|cuda|cuda12|rocm]   (default cpu)
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
    TOOLKIT_IMAGE=""
    VGPU_GPU=""
    ;;
cuda)
    FROM_IMAGE="docker.io/nvidia/cuda:13.5.0-devel-ubuntu26.04"
    TOOLKIT_IMAGE=""
    VGPU_GPU="nvidia/h100"
    ;;
cuda12)
    # CUDA 12 for compilers that do not support 13 yet (clang); Ubuntu 26.04 has CUDA 13 only
    FROM_IMAGE="docker.io/nvidia/cuda:12.9.2-devel-ubuntu24.04"
    TOOLKIT_IMAGE=""
    VGPU_GPU="nvidia/h100"
    ;;
rocm)
    # ROCm from its -full image (8GB, too large for a runner pulling it as a job container),
    #  trimmed (scripts/trim_rocm.sh), onto plain Ubuntu
    FROM_IMAGE="docker.io/library/ubuntu:26.04"
    TOOLKIT_IMAGE="docker.io/rocm/dev-ubuntu-26.04:7.14.1-full"
    VGPU_GPU="amd/mi300x"
    ;;
*)
    echo "unknown flavor '${FLAVOR}', expected cpu, cuda, cuda12 or rocm" >&2
    exit 1
    ;;
esac

IMAGE=${IMAGE:-"ghcr.io/0xz/hpc-containers"} # tagged :<flavor>
# cpu: no simulator, so no CMake toolchain file, and no GPU in the image description
CPU_ARGS=()
[[ "${FLAVOR}" != cpu ]] || CPU_ARGS=(--build-arg CMAKE_TOOLCHAIN= --build-arg "GPU_DESCRIPTION=no GPU")
docker build \
    --build-arg FROM_IMAGE="${FROM_IMAGE}" \
    ${TOOLKIT_IMAGE:+--build-arg TOOLKIT_IMAGE="${TOOLKIT_IMAGE}"} \
    --build-arg FLAVOR="${FLAVOR}" \
    --build-arg VGPU_GPU="${VGPU_GPU}" \
    "${CPU_ARGS[@]}" \
    ${MARCH:+--build-arg MARCH="${MARCH}"} \
    -t "${IMAGE}:${FLAVOR}" .
