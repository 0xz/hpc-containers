#!/usr/bin/env bash
# usage: ./build.sh [cuda|rocm]   (default cuda)
#
# the toolkits come from their vendors' own images: nvcc is not ours to redistribute
set -ex
CWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" && cd "$CWD"

FLAVOR=${1:-cuda}
case "${FLAVOR}" in
cuda)
    FROM_IMAGE="docker.io/nvidia/cuda:13.5.0-devel-ubuntu26.04"
    VGPU_GPU="nvidia/h100"
    ;;
rocm)
    FROM_IMAGE="docker.io/rocm/dev-ubuntu-26.04:7.14.1-full"
    VGPU_GPU="amd/mi300x"
    ;;
*)
    echo "unknown flavor '${FLAVOR}', expected cuda or rocm" >&2
    exit 1
    ;;
esac

IMAGE=${IMAGE:-"ghcr.io/0xz/hpc-containers"} # tagged :<flavor>
docker build \
    --build-arg FROM_IMAGE="${FROM_IMAGE}" \
    --build-arg FLAVOR="${FLAVOR}" \
    --build-arg VGPU_GPU="${VGPU_GPU}" \
    ${MARCH:+--build-arg MARCH="${MARCH}"} \
    -t "${IMAGE}:${FLAVOR}" .
