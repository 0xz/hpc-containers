# hpc-containers

Development images with Open MPI (PMIx, UCX) and parallel HDF5 (MPI-IO, subfiling, Fortran) on a
GPU toolkit, with [PantheonSim](https://github.com/pantheongpu/pantheonsim) as the GPU: CUDA and
HIP code builds and runs on a machine with no GPU. The `cpu` image has the same MPI and HDF5 on
plain Ubuntu, without a GPU toolkit or simulator.

| Image | Base | GPU (`VGPU_GPU`) |
|---|---|---|
| `ghcr.io/0xz/hpc-containers:cpu` | `ubuntu:26.04` | none |
| `ghcr.io/0xz/hpc-containers:cuda` | `nvidia/cuda:13.5.0-devel-ubuntu26.04` | `nvidia/h100` |
| `ghcr.io/0xz/hpc-containers:rocm` | `rocm/dev-ubuntu-26.04:7.14.1-full` | `amd/mi300x` |

Each push to master also tags `<target>-<short sha>`.

## Use

```bash
docker run --rm -it -v "$PWD:/work" -w /work ghcr.io/0xz/hpc-containers:cuda
mpicc ...                          # /opt/mpi, on PATH
cmake -DHDF5_ROOT=$HDF5_ROOT ...   # /opt/hdf5
vgpu run ./gpu_program             # GPU code runs under vgpu, which puts the simulator's libraries in place
vgpu run mpirun -n 2 ./gpu_program
```

- `nvcc` on PATH is the simulator's wrapper around the real one: it adds `-cudart shared`, since
  the static CUDA runtime cannot reach a simulated driver. `CMAKE_TOOLCHAIN_FILE` does the same
  for CMake projects.
- The simulated GPU is functional only: timings mean nothing.
- MPI and HDF5 are built with `-O3 -march=x86-64-v3` (AVX2), not `native`, so the images run on
  any recent x86-64 CPU. `MARCH=native ./build.sh` for a local build.
- `mpirun` as root and oversubscription are allowed (`OMPI_ALLOW_RUN_AS_ROOT`,
  `PRTE_MCA_rmaps_default_mapping_policy`).

## Build

```bash
./build.sh       # cpu, or ./build.sh cuda|rocm; MARCH=native ./build.sh for a local-only build
docker run --rm ghcr.io/0xz/hpc-containers:cpu /opt/hpc/test/run.sh cpu
```

`build.sh` picks the vendor base image (`FROM_IMAGE`) and simulated GPU per flavor, the
`Dockerfile` copies the repo to `/opt/hpc` and runs `run.sh` in the image, which builds
PantheonSim at `PANTHEONSIM_REF` (against the image's CUDA toolkit for `cuda`, its CUDA libraries
must match the toolkit version; AMD side only for `rocm`), then MPI and HDF5.

| Path | What |
|---|---|
| `build.sh` | `[cpu\|cuda\|rocm]` (default cpu): `docker build` with the base image and build args for that flavor |
| `Dockerfile` | copies the repo in, runs `run.sh`, sets the environment |
| `run.sh` | `<cpu\|cuda\|rocm>`, in the image: deps, PantheonSim (not cpu), MPI, HDF5, linkage checks |
| `scripts/build_mpi.sh` | `<host\|cuda\|rocm>`: PMIx → UCX → Open MPI into `/opt/mpi` |
| `scripts/build_hdf5.sh` | parallel HDF5 with subfiling and Fortran into `/opt/hdf5` |
| `scripts/check_linkage.sh` | `PREFIX [ALLOWED...]`: fails if anything links MPI-stack libraries from elsewhere |
| `test/run.sh` | `<cpu\|cuda\|rocm>`: MPI, parallel HDF5, and GPU-aware MPI on the simulated GPU (not cpu) |

## CI

`.github/workflows/build.yml` builds and tests the three images on every pull request and pushes them
from master with the workflow's own token. The GPU-aware MPI test does not fail the job.

## Updating versions

- **Open MPI, PMIx, UCX, HDF5**: defaults at the top of `scripts/build_mpi.sh` and
  `scripts/build_hdf5.sh`. PMIx follows the version Open MPI bundles:
  `gh api "repos/open-mpi/ompi/contents/3rd-party?ref=v$MPI_VER" -q '.[] | "\(.name) \(.sha)"'`.
  Use the Open MPI release tarball, not a tag archive: only the tarball has `configure` and the
  bundled PMIx/PRRTE.
- **UCX** builds with `-Werror` and no switch to turn it off. If a new compiler breaks it, prefer
  a newer UCX, otherwise add a narrow `-Wno-error=<x>`.
- **CUDA / ROCm**: `FROM_IMAGE` per flavor in `build.sh`. On Ubuntu 26.04, NVIDIA has
  CUDA 13.x only, and AMD has the `rocm/dev-ubuntu-26.04` images but no apt repository yet.
- **PantheonSim**: `PANTHEONSIM_REF` in `run.sh`, a commit on its main branch until a release has
  what is needed.
