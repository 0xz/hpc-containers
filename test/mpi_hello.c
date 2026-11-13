// every rank passes its rank round a ring, then all ranks agree on the sum
#include <mpi.h>
#include <stdio.h>

int main(int argc, char** argv) {
  MPI_Init(&argc, &argv);
  int rank, size;
  MPI_Comm_rank(MPI_COMM_WORLD, &rank);
  MPI_Comm_size(MPI_COMM_WORLD, &size);

  int const next = (rank + 1) % size, prev = (rank + size - 1) % size;
  int got = -1;
  MPI_Sendrecv(&rank, 1, MPI_INT, next, 0, &got, 1, MPI_INT, prev, 0, MPI_COMM_WORLD,
               MPI_STATUS_IGNORE);

  int sum = 0;
  MPI_Allreduce(&rank, &sum, 1, MPI_INT, MPI_SUM, MPI_COMM_WORLD);

  int const ok = got == prev && sum == size * (size - 1) / 2;
  if (!ok) fprintf(stderr, "rank %d: got %d from %d, sum %d\n", rank, got, prev, sum);
  if (rank == 0 && ok) printf("mpi_hello OK on %d ranks\n", size);
  MPI_Finalize();
  return ok ? 0 : 1;
}
