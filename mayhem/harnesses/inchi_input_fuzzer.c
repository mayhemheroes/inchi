// inchi_input_fuzzer.c — fuzz InChI's InChI-STRING parsing surface.
//
// Adapted from the OSS-Fuzz harness (google/oss-fuzz projects/inchi). The input is treated
// as a (null-terminated) InChI string and pushed through the three string-consuming public
// API entry points:
//   GetINCHIKeyFromINCHI — parse InChI string -> compute the 27-char InChIKey (+ extra hashes)
//   GetINCHIfromINCHI    — re-canonicalize an InChI string -> InChI string (normalization)
//   GetStructFromINCHI   — parse InChI string -> reconstruct the molecular structure (atoms/bonds/stereo)
// These cover the readinch.c / ichi* string parsers and the structure rebuilder.

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "inchi_api.h"

// Returning early on size==SIZE_MAX: appending the null terminator would wrap size+1 to 0.
static const size_t kSizeMax = (size_t)-1;

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {

  if (size == kSizeMax)
    return 0;

  char *szINCHISource = (char *)malloc(sizeof(char) * (size + 1));
  if (!szINCHISource)
    return 0;
  memcpy(szINCHISource, data, size);
  szINCHISource[size] = '\0'; // InChI string must be null-terminated

  // Buffer lengths from the InChI API reference (InChIKey is 27 chars + NUL).
  char szINCHIKey[28], szXtra1[65], szXtra2[65];
  GetINCHIKeyFromINCHI(szINCHISource, 0, 0, szINCHIKey, szXtra1, szXtra2);

  inchi_InputINCHI inpInChI;
  inpInChI.szInChI = szINCHISource;
  inpInChI.szOptions = NULL;

  inchi_Output out;
  memset(&out, 0, sizeof(out));
  GetINCHIfromINCHI(&inpInChI, &out);

  inchi_OutputStruct outStruct;
  memset(&outStruct, 0, sizeof(outStruct));
  GetStructFromINCHI(&inpInChI, &outStruct);

  free(szINCHISource);
  FreeINCHI(&out);
  FreeStructFromINCHI(&outStruct);

  return 0;
}
