#!/usr/bin/env bash
# usage: run.sh <cuda|rocm>   (run inside the image by the Dockerfile, as root)
#
# PantheonSim, then PMIx -> UCX -> Open MPI into /opt/mpi, then parallel HDF5 into /opt/hdf5
#
# env: MARCH (default x86-64-v3), PANTHEONSIM_REF, NPROC
set -ex
CWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FLAVOR=${1:-${FLAVOR:-}}
export MARCH=${MARCH:-x86-64-v3}
PANTHEONSIM_GIT="https://github.com/pantheongpu/pantheonsim"
PANTHEONSIM_REF=${PANTHEONSIM_REF:-"1dc4331175956285e3da895444dd0dadccb21b08"}
WORK_DIR=/tmp/work

case "${FLAVOR}" in
cuda | rocm) ;;
*)
    echo "unknown flavor '${FLAVOR}', expected cuda or rocm" >&2
    exit 1
    ;;
esac

apt-get update
apt-get install -y --no-install-recommends \
    build-essential gfortran autoconf automake libtool flex bison perl python3 git wget bzip2 \
    ca-certificates cmake ninja-build file pkg-config libevent-dev libhwloc-dev zlib1g-dev

if [[ "${FLAVOR}" == cuda ]]; then
    # the headers of every library the simulator stands in for, as its github action installs them
    v=$(echo "${CUDA_VERSION%.*}" | tr . -)
    nvvm="cuda-nvvm-$v"
    [[ "${CUDA_VERSION%%.*}" -lt 13 ]] || nvvm="libnvvm-$v"
    apt-get install -y --no-install-recommends \
        "cuda-nvcc-$v" "cuda-cudart-dev-$v" "cuda-crt-$v" "$nvvm" \
        "cuda-nvml-dev-$v" "cuda-cupti-dev-$v" "cuda-nvrtc-dev-$v" "libcublas-dev-$v" \
        "libcufft-dev-$v" "libcurand-dev-$v" "libcusparse-dev-$v" "libnvjpeg-dev-$v" \
        "libcusolver-dev-$v" "libnpp-dev-$v" "libnvjitlink-dev-$v" "cuda-profiler-api-$v"
fi

mkdir -p "${WORK_DIR}"

# the simulator: its CUDA libraries are built against this toolkit's headers, without nvcc (rocm)
#  only its AMD side is built
(
    mkdir -p "${WORK_DIR}/pantheonsim" && cd "${WORK_DIR}/pantheonsim"
    git init -q . && git remote add origin "${PANTHEONSIM_GIT}"
    git fetch -q --depth 1 origin "${PANTHEONSIM_REF}" && git checkout -q FETCH_HEAD
    cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
    cmake --build build -j"$(ci/jobs.sh -p release)"
    scripts/package-build.sh build /opt/pantheonsim
    cp LICENSE THIRD_PARTY_NOTICES.md /opt/pantheonsim/
    echo "${PANTHEONSIM_GIT} ${PANTHEONSIM_REF}" >/opt/pantheonsim/SOURCE
)
# CMake links CUDA with the static runtime by default, which cannot reach the simulator
cat >/opt/pantheonsim/toolchain.cmake <<'EOF'
set(CMAKE_CUDA_RUNTIME_LIBRARY Shared CACHE STRING "CUDA runtime library")
EOF

(
    cd "${WORK_DIR}"
    INSTALL_DIR=/opt/mpi "${CWD}/scripts/build_mpi.sh" "${FLAVOR}"
    "${CWD}/scripts/check_linkage.sh" /opt/mpi
    MPI=/opt/mpi INSTALL_DIR=/opt/hdf5 "${CWD}/scripts/build_hdf5.sh"
    "${CWD}/scripts/check_linkage.sh" /opt/hdf5 /opt/mpi
)

if [[ "${FLAVOR}" == rocm ]]; then
    # hipcc with no --offload-arch asks this which GPUs are present: the simulated one
    ln -sfn /opt/pantheonsim/bin/rocm_agent_enumerator /opt/rocm/bin/rocm_agent_enumerator
fi

rm -rf "${WORK_DIR}" /var/lib/apt/lists/*
apt-get clean
