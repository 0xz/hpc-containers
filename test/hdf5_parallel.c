// each rank writes its slice of one dataset collectively, through the MPI-IO driver and then the
//  subfiling driver, and reads the whole dataset back
#include <hdf5.h>
#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>

#define N 1024  // elements per rank

static int check(hid_t fapl, char const* file, int rank, int size) {
  hsize_t const total = (hsize_t)N * size, count = N, offset = (hsize_t)N * rank;

  hid_t f = H5Fcreate(file, H5F_ACC_TRUNC, H5P_DEFAULT, fapl);
  if (f < 0) return 1;
  hid_t filespace = H5Screate_simple(1, &total, NULL);
  hid_t dset = H5Dcreate2(f, "d", H5T_NATIVE_INT, filespace, H5P_DEFAULT, H5P_DEFAULT,
                          H5P_DEFAULT);
  H5Sselect_hyperslab(filespace, H5S_SELECT_SET, &offset, NULL, &count, NULL);
  hid_t memspace = H5Screate_simple(1, &count, NULL);
  hid_t dxpl = H5Pcreate(H5P_DATASET_XFER);
  H5Pset_dxpl_mpio(dxpl, H5FD_MPIO_COLLECTIVE);

  int* buf = malloc(sizeof(int) * total);
  for (int i = 0; i < N; ++i) buf[i] = rank * N + i;
  herr_t err = H5Dwrite(dset, H5T_NATIVE_INT, memspace, filespace, dxpl, buf);
  H5Pclose(dxpl), H5Sclose(memspace), H5Sclose(filespace), H5Dclose(dset), H5Fclose(f);
  if (err < 0) return free(buf), 1;

  int bad = 0;
  f = H5Fopen(file, H5F_ACC_RDONLY, fapl);
  dset = H5Dopen2(f, "d", H5P_DEFAULT);
  if (H5Dread(dset, H5T_NATIVE_INT, H5S_ALL, H5S_ALL, H5P_DEFAULT, buf) < 0) bad = 1;
  for (hsize_t i = 0; !bad && i < total; ++i) bad = buf[i] != (int)i;
  H5Dclose(dset), H5Fclose(f), free(buf);
  return bad;
}

int main(int argc, char** argv) {
  int provided;  // subfiling needs MPI_THREAD_MULTIPLE
  MPI_Init_thread(&argc, &argv, MPI_THREAD_MULTIPLE, &provided);
  int rank, size;
  MPI_Comm_rank(MPI_COMM_WORLD, &rank);
  MPI_Comm_size(MPI_COMM_WORLD, &size);

  hid_t fapl = H5Pcreate(H5P_FILE_ACCESS);
  H5Pset_fapl_mpio(fapl, MPI_COMM_WORLD, MPI_INFO_NULL);
  int bad = check(fapl, "mpio.h5", rank, size);
  H5Pclose(fapl);

  if (provided == MPI_THREAD_MULTIPLE) {
    fapl = H5Pcreate(H5P_FILE_ACCESS);
    H5Pset_mpi_params(fapl, MPI_COMM_WORLD, MPI_INFO_NULL);
    H5Pset_fapl_subfiling(fapl, NULL);
    bad |= check(fapl, "subfiling.h5", rank, size) << 1;
    H5Pclose(fapl);
  } else {
    bad |= 4;
  }

  int any = 0;
  MPI_Allreduce(&bad, &any, 1, MPI_INT, MPI_BOR, MPI_COMM_WORLD);
  if (rank == 0) {
    if (any & 1) fprintf(stderr, "hdf5_parallel: mpio failed\n");
    if (any & 2) fprintf(stderr, "hdf5_parallel: subfiling failed\n");
    if (any & 4) fprintf(stderr, "hdf5_parallel: no MPI_THREAD_MULTIPLE for subfiling\n");
    if (!any) printf("hdf5_parallel OK on %d ranks (mpio, subfiling)\n", size);
  }
  MPI_Finalize();
  return any ? 1 : 0;
}
