// GPU-aware MPI: rank 0 fills a device buffer and sends the device pointer to rank 1, which
//  receives straight into device memory and checks it on the host
#include <mpi.h>
#include <cstdio>
#include <vector>

#if defined(__HIP__)
#include <hip/hip_runtime.h>
#define gpuMalloc hipMalloc
#define gpuFree hipFree
#define gpuMemcpy hipMemcpy
#define gpuMemcpyDeviceToHost hipMemcpyDeviceToHost
#define gpuDeviceSynchronize hipDeviceSynchronize
#else
#include <cuda_runtime.h>
#define gpuMalloc cudaMalloc
#define gpuFree cudaFree
#define gpuMemcpy cudaMemcpy
#define gpuMemcpyDeviceToHost cudaMemcpyDeviceToHost
#define gpuDeviceSynchronize cudaDeviceSynchronize
#endif

constexpr int N = 1 << 16;

__global__ void fill(int* p) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < N) p[i] = i;
}

int main(int argc, char** argv) {
  MPI_Init(&argc, &argv);
  int rank, size;
  MPI_Comm_rank(MPI_COMM_WORLD, &rank);
  MPI_Comm_size(MPI_COMM_WORLD, &size);
  if (size != 2) {
    if (rank == 0) std::fprintf(stderr, "mpi_device: run on 2 ranks\n");
    MPI_Abort(MPI_COMM_WORLD, 2);
  }

  int* d = nullptr;
  if (gpuMalloc(&d, N * sizeof(int)) != 0) {
    std::fprintf(stderr, "rank %d: device alloc failed\n", rank);
    MPI_Abort(MPI_COMM_WORLD, 3);
  }

  int bad = 0;
  if (rank == 0) {
    fill<<<(N + 255) / 256, 256>>>(d);
    gpuDeviceSynchronize();
    MPI_Send(d, N, MPI_INT, 1, 0, MPI_COMM_WORLD);
  } else {
    MPI_Recv(d, N, MPI_INT, 0, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
    std::vector<int> h(N);
    gpuMemcpy(h.data(), d, N * sizeof(int), gpuMemcpyDeviceToHost);
    for (int i = 0; i < N && !bad; ++i) bad = h[i] != i;
  }
  gpuFree(d);

  int any = 0;
  MPI_Allreduce(&bad, &any, 1, MPI_INT, MPI_MAX, MPI_COMM_WORLD);
  if (rank == 0) std::printf("mpi_device %s\n", any ? "FAILED: wrong data" : "OK");
  MPI_Finalize();
  return any;
}
