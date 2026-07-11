#!/usr/bin/env bash
#
# inchi/mayhem/build.sh — build IUPAC InChI's two libFuzzer harnesses (+ standalone reproducers)
# and the golden-roundtrip test oracle, all instrumented with $SANITIZER_FLAGS (ASan+UBSan).
#
# Fuzzed surface:
#   inchi_input_fuzzer   — InChI STRING parsers: GetINCHIKeyFromINCHI / GetINCHIfromINCHI /
#                          GetStructFromINCHI (readinch.c + structure rebuilder).
#   inchi_molfile_fuzzer — MDL Molfile/SDF text parser via MakeINCHIFromMolfileText
#                          (mol_fmt1..4.c / mol2atom.c + normalizer + InChI generator).
#
# Build contract comes from the org base ENV (CC/CXX/SANITIZER_FLAGS/LIB_FUZZING_ENGINE/SRC/
# STANDALONE_FUZZ_MAIN/OUT). We compile the InChI library ITSELF with $SANITIZER_FLAGS + libFuzzer
# coverage so the parser code (not just the harness) is instrumented and the seed corpus measurably
# expands coverage.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# `=` (not `:=`) for SANITIZER_FLAGS so an explicit empty --build-arg builds with NO sanitizers.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${OUT:=/mayhem}"
: "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE OUT MAYHEM_JOBS

# Where this script and the harnesses live (works regardless of CWD).
MAYHEM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$MAYHEM_DIR/.." && pwd)"
HARNESS_DIR="$MAYHEM_DIR/harnesses"
SRCROOT="$REPO_ROOT/INCHI-1-SRC"

cd "$SRCROOT"

INC="-I INCHI_BASE/src/ -I INCHI_API/libinchi/src/ -I INCHI_API/libinchi/src/ixa/"

# UBSan relaxation (NARROW, library compile only):
#   ichicano.c:133  FillMaxMinClock()  intentionally shifts a signed clock_t until overflow to
#                   discover the platform's max clock value (`while (0 < ((val1<<=1),(val1|=1)))`).
#                   With -fno-sanitize-recover=all this signed-shift/overflow UB ABORTS on the very
#                   first call — i.e. on EVERY input (even empty), so it floods every run and the
#                   harness never fuzzes. We disable ONLY shift + signed-integer-overflow on the
#                   library; ASan + the rest of UBSan (null-deref, OOB, type-mismatch, etc.) stay
#                   halting. (A real null-memcpy UB in ichicano.c:2025 is intentionally kept halting.)
UBSAN_RELAX="-fno-sanitize=shift -fno-sanitize=signed-integer-overflow"

# ── 1) Build the InChI static library WITH sanitizers + libFuzzer coverage ─────────────────────────
#    -DTARGET_API_LIB selects the DLL/library build; exclude ichimain.c (the inchi-1 CLI main()).
BUILD="$SRCROOT/mayhem-build"
rm -rf "$BUILD"; mkdir -p "$BUILD"
SRC_FILES=$(ls INCHI_BASE/src/*.c INCHI_API/libinchi/src/*.c INCHI_API/libinchi/src/ixa/*.c | grep -v ichimain.c)

# Coverage for the library: append fuzzer-no-link only when LIB_FUZZING_ENGINE is libFuzzer
# (so a non-libFuzzer engine / sanitizer-less build still works).
COV=""
case "$LIB_FUZZING_ENGINE" in *fuzzer*) COV="-fsanitize=fuzzer-no-link";; esac

# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $UBSAN_RELAX $COV $DEBUG_FLAGS -w -DTARGET_API_LIB -c $SRC_FILES
LIBINCHI="$BUILD/libinchi.a"
rm -f "$LIBINCHI"; ar rcs "$LIBINCHI" ./*.o
rm -f ./*.o
echo "built $LIBINCHI"

# Standalone run-once driver (no libFuzzer runtime) compiled once.
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $UBSAN_RELAX $DEBUG_FLAGS $INC -c "$HARNESS_DIR/standalone_main.c" -o "$BUILD/standalone_main.o"

# ── 2) Build each harness twice: libFuzzer (-> $OUT/<name>) + standalone reproducer ───────────────
for harness in inchi_input_fuzzer inchi_molfile_fuzzer; do
  # shellcheck disable=SC2086
  $CC $SANITIZER_FLAGS $UBSAN_RELAX $DEBUG_FLAGS $INC \
      "$HARNESS_DIR/$harness.c" $LIB_FUZZING_ENGINE "$LIBINCHI" -lm \
      -o "$OUT/$harness"

  # shellcheck disable=SC2086
  $CC $SANITIZER_FLAGS $UBSAN_RELAX $DEBUG_FLAGS $INC \
      "$HARNESS_DIR/$harness.c" "$BUILD/standalone_main.o" "$LIBINCHI" -lm \
      -o "$OUT/$harness-standalone"

  echo "built $harness (+ standalone)"
done

# Ship the dictionaries next to the binaries (Mayhemfile references them under /mayhem).
cp -f "$MAYHEM_DIR"/*.dict "$OUT"/ 2>/dev/null || true

# ── 3) Build the golden-roundtrip test oracle (run by mayhem/test.sh). Sanitized so the KAT also
#       acts as an ASan/UBSan check on the canonical caffeine path. ───────────────────────────────
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $UBSAN_RELAX $DEBUG_FLAGS $INC \
    "$HARNESS_DIR/inchi_golden_test.c" "$LIBINCHI" -lm \
    -o "$OUT/inchi_golden_test"
echo "built inchi_golden_test"

echo "build.sh complete:"
ls -la "$OUT/inchi_input_fuzzer" "$OUT/inchi_molfile_fuzzer" \
       "$OUT/inchi_input_fuzzer-standalone" "$OUT/inchi_molfile_fuzzer-standalone" \
       "$OUT/inchi_golden_test" 2>&1 || true
