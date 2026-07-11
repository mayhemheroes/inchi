// standalone_main.c — generic run-once driver for the libFuzzer harnesses (no libFuzzer runtime).
// Reads a single input file and calls LLVMFuzzerTestOneInput once, so a Mayhem-found testcase can
// be replayed under a debugger / ASan outside the fuzzing engine.
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

int LLVMFuzzerTestOneInput(const uint8_t *pData, size_t size);

int main(int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "usage: %s <input-file>\n", argv[0]);
    return 1;
  }
  FILE *f = fopen(argv[1], "rb");
  if (!f) {
    fprintf(stderr, "failed to open %s\n", argv[1]);
    return 2;
  }
  fseek(f, 0, SEEK_END);
  long size = ftell(f);
  fseek(f, 0, SEEK_SET);
  if (size < 0) { fclose(f); return 3; }
  uint8_t *pData = (uint8_t *)malloc((size_t)size + 1);
  if (!pData) { fclose(f); return 3; }
  size_t got = size ? fread(pData, 1, (size_t)size, f) : 0;
  fclose(f);
  LLVMFuzzerTestOneInput(pData, got);
  free(pData);
  return 0;
}
