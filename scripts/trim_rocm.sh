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
# /opt/rocm is /etc/alternatives/rocm -> /opt/rocm-X.Y.Z: the absolute link dangles on plain
#  Ubuntu, relink it to the copied tree
for l in "${OUT}"/rocm*; do
    [[ -L "${l}" ]] || continue
    ln -sfn "$(basename "$(readlink -f "/opt/$(basename "${l}")")")" "${l}"
done
ls -l "${OUT}"
du -sh "${OUT}"

# libraries (and their data: kernels, databases) no code built here uses
LIBS='MIOpen|miopen|rocblas|hipblas|hipblaslt|hipsparselt|rocsolver|hipsolver|rocfft|hipfft'
LIBS+='|rocsparse|hipsparse|rccl|rocrand|hiprand|rocalution|migraphx|rocwmma|hiptensor|rocroller'
LIBS+='|composable_kernel|ck_|mivisionx|rpp|rocdecode|rocjpeg|roctx|rocprofiler|roctracer|omni'
find "${OUT}" \( -type f -o -type l \) -regextype posix-extended \
    -regex ".*/lib(${LIBS})[^/]*\.(so[.0-9]*|a)$" -delete
find "${OUT}" -depth -type d -regextype posix-extended \
    -regex ".*/(lib|share)/(${LIBS})[^/]*" -exec rm -rf {} +
du -sh "${OUT}"
