# see build.sh for FROM_IMAGE and the other build args per flavor, run.sh for what is built

ARG FROM_IMAGE
FROM $FROM_IMAGE

ARG FLAVOR
ARG VGPU_GPU
# cpu: no simulator, so no toolchain file (empty) and no GPU in the description
ARG CMAKE_TOOLCHAIN=/opt/pantheonsim/toolchain.cmake
ARG GPU_DESCRIPTION="PantheonSim as the GPU"
# portable, not native: the image runs on whatever CPU pulls it
ARG MARCH=x86-64-v3

USER root
ENV DEBIAN_FRONTEND=noninteractive

COPY . /opt/hpc
RUN chmod +x /opt/hpc/run.sh && MARCH=${MARCH} /opt/hpc/run.sh ${FLAVOR}

# sim bin/ first: its nvcc is the real one plus -cudart shared, its nvidia-smi / rocm-smi the
#  simulated GPU. The shim is not on LD_LIBRARY_PATH: `vgpu run <program>` puts it there.
ENV PATH=/opt/pantheonsim/bin:/opt/mpi/bin:/opt/hdf5/bin:${PATH} \
    VGPU_SHIM_DIR=/opt/pantheonsim/shim \
    VGPU_GPU=${VGPU_GPU} \
    CMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN} \
    MPI_HOME=/opt/mpi \
    HDF5_ROOT=/opt/hdf5 \
    OMPI_ALLOW_RUN_AS_ROOT=1 \
    OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1 \
    PRTE_MCA_rmaps_default_mapping_policy=:oversubscribe

LABEL org.opencontainers.image.source="https://github.com/0xz/hpc-containers" \
      org.opencontainers.image.description="Open MPI + parallel HDF5 on ${FLAVOR}, ${GPU_DESCRIPTION}"
