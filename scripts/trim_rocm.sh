#!/usr/bin/env bash
# usage: trim_rocm.sh <out dir>   (in the rocm stage of the Dockerfile, as root)
#
# ROCm's dev images for Ubuntu 26.04 are -full only (8GB compressed, too large for a GitHub
#  runner to pull as a job container). Copies /opt/rocm* to <out dir> less the math and ML
#  libraries and their kernel / database files: HIP, the compiler, the runtime, rocm-smi, and the
#  header only rocPRIM / rocThrust / hipCUB stay. Nothing is copied from an image without ROCm
#  (the cpu and cuda flavors), so their stage is empty
set -e
OUT=${1:?out dir}
mkdir -p "${OUT}"
ls -d /opt/rocm* >/dev/null 2>&1 || exit 0
cp -a /opt/rocm* "${OUT}/"
# links out of /opt dangle on plain Ubuntu: update-alternatives makes /opt/rocm/{bin,lib,include,..}
#  (ROCm 7.14: /opt/rocm/core-7.14/..), or /opt/rocm itself (older), links via /etc/alternatives.
#  Point each at what it resolves to here, a path under /opt
find "${OUT}" -type l -lname '/*' ! -lname '/opt/*' -print0 |
    while IFS= read -r -d '' l; do
        ln -sfn "$(readlink -f "/opt/${l#"${OUT}/"}")" "${l}"
        echo "${l#"${OUT}/"} -> $(readlink "${l}")"
    done
ls -l "${OUT}" "${OUT}/rocm"
du -sh "${OUT}"

# libraries (and their data: kernels, databases) no code built here uses
LIBS='MIOpen|miopen|rocblas|hipblas|hipblaslt|hipsparselt|rocsolver|hipsolver|rocfft|hipfft'
LIBS+='|rocsparse|hipsparse|rccl|rocrand|hiprand|rocalution|migraphx|rocwmma|hiptensor|rocroller'
LIBS+='|composable_kernel|ck_|mivisionx|rpp|rocdecode|rocjpeg|roctx|roctracer|omni'
# rocprofiler-register stays: HIP and HSA link it
LIBS+='|rocprofiler-sdk|rocprofiler-compute|rocprofiler-systems'
find "${OUT}" \( -type f -o -type l \) -regextype posix-extended \
    -regex ".*/lib(${LIBS})[^/]*\.(so[.0-9]*|a)$" -delete
find "${OUT}" -depth -type d -regextype posix-extended \
    -regex ".*/(lib|share)/(${LIBS})[^/]*" -exec rm -rf {} +
du -sh "${OUT}"
