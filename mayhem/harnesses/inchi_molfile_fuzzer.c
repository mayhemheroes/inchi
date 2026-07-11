// inchi_molfile_fuzzer.c — fuzz InChI's MOL/SDF (Molfile) parsing surface.
//
// The input bytes are treated as the TEXT of an MDL Molfile/SDF and handed to
//   MakeINCHIFromMolfileText(moltext, options, &result)
// which drives the full CTfile reader (mol_fmt1..4.c / mol2atom.c), the structure
// normalizer, and the InChI generator. This is the rich attacker-controlled parser
// surface (atom/bond counts, coordinates, charges, stereo, V2000/V3000 blocks,
// property lines) that the InChI-string harness does not reach.

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "inchi_api.h"

static const size_t kSizeMax = (size_t)-1;

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {

  if (size == kSizeMax)
    return 0;

  char *moltext = (char *)malloc(sizeof(char) * (size + 1));
  if (!moltext)
    return 0;
  memcpy(moltext, data, size);
  moltext[size] = '\0'; // Molfile text must be null-terminated

  inchi_Output out;
  memset(&out, 0, sizeof(out));

  // Empty options string => default InChI generation. options is non-const in the API.
  char options[] = "";
  MakeINCHIFromMolfileText(moltext, options, &out);

  FreeINCHI(&out);
  free(moltext);
  return 0;
}
