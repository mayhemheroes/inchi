// inchi_golden_test.c — known-answer (golden round-trip) oracle for InChI.
//
// Two byte-exact checks over a real molecule (caffeine), driving the same library code the
// fuzzers exercise but asserting CORRECT output (so a no-op / "return 0" patch fails):
//
//   1. MOL -> InChI : feed caffeine's Molfile text through MakeINCHIFromMolfileText and assert the
//      emitted InChI string equals the canonical InChI for caffeine.
//   2. InChI -> InChIKey : feed that InChI string through GetINCHIKeyFromINCHI and assert the
//      27-char InChIKey equals caffeine's well-known InChIKey.
//
// The Molfile is read from the upstream test fixture (argv[1]); the expected answers are baked in.
// Exit 0 iff BOTH checks pass; nonzero (and a diagnostic) otherwise.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "inchi_api.h"

// Canonical InChI + InChIKey for caffeine (C8H10N4O2).
static const char *EXPECT_INCHI =
    "InChI=1S/C8H10N4O2/c1-10-4-9-6-5(10)7(13)12(3)8(14)11(6)2/h4H,1-3H3";
static const char *EXPECT_KEY = "RYYVLZVUVIJVGH-UHFFFAOYSA-N";

static char *read_file(const char *path) {
  FILE *f = fopen(path, "rb");
  if (!f) { fprintf(stderr, "cannot open %s\n", path); return NULL; }
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  fseek(f, 0, SEEK_SET);
  if (n < 0) { fclose(f); return NULL; }
  char *buf = (char *)malloc((size_t)n + 1);
  if (!buf) { fclose(f); return NULL; }
  size_t got = n ? fread(buf, 1, (size_t)n, f) : 0;
  buf[got] = '\0';
  fclose(f);
  return buf;
}

int main(int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "usage: %s <caffeine.mol>\n", argv[0]);
    return 2;
  }
  char *moltext = read_file(argv[1]);
  if (!moltext)
    return 2;

  int failures = 0;

  // ── Check 1: MOL -> InChI ──────────────────────────────────────────────────────
  inchi_Output out;
  memset(&out, 0, sizeof(out));
  char options[] = "";
  int rc = MakeINCHIFromMolfileText(moltext, options, &out);
  if (rc != 0 && rc != 1 /* 1 = warning, still produces InChI */) {
    fprintf(stderr, "FAIL mol2inchi: rc=%d msg=%s\n", rc, out.szMessage ? out.szMessage : "");
    failures++;
  } else if (!out.szInChI || strcmp(out.szInChI, EXPECT_INCHI) != 0) {
    fprintf(stderr, "FAIL mol2inchi:\n  expected: %s\n  got:      %s\n",
            EXPECT_INCHI, out.szInChI ? out.szInChI : "(null)");
    failures++;
  } else {
    fprintf(stderr, "PASS mol2inchi: %s\n", out.szInChI);
  }
  // Keep a copy of the produced InChI for check 2 (fall back to the expected string).
  char inchi_buf[1024];
  snprintf(inchi_buf, sizeof(inchi_buf), "%s",
           (out.szInChI && *out.szInChI) ? out.szInChI : EXPECT_INCHI);
  FreeINCHI(&out);
  free(moltext);

  // ── Check 2: InChI -> InChIKey ─────────────────────────────────────────────────
  char key[28], xtra1[65], xtra2[65];
  int krc = GetINCHIKeyFromINCHI(inchi_buf, 0, 0, key, xtra1, xtra2);
  if (krc != 0 /* INCHIKEY_OK */) {
    fprintf(stderr, "FAIL inchi2key: rc=%d\n", krc);
    failures++;
  } else if (strcmp(key, EXPECT_KEY) != 0) {
    fprintf(stderr, "FAIL inchi2key:\n  expected: %s\n  got:      %s\n", EXPECT_KEY, key);
    failures++;
  } else {
    fprintf(stderr, "PASS inchi2key: %s\n", key);
  }

  return failures ? 1 : 0;
}
