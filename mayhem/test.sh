#!/usr/bin/env bash
#
# inchi/mayhem/test.sh — RUN the golden-roundtrip oracle built by mayhem/build.sh and emit a CTRF
# summary. exit 0 iff every known-answer check passed.
#
# PATCH-grade oracle: the oracle drives caffeine's Molfile through MakeINCHIFromMolfileText and
# asserts the emitted InChI string is BYTE-EXACT against the canonical caffeine InChI, then runs that
# InChI through GetINCHIKeyFromINCHI and asserts the 27-char InChIKey equals caffeine's well-known
# key (RYYVLZVUVIJVGH-UHFFFAOYSA-N). A no-op / "return 0" patch (or any change that perturbs the
# canonical output) cannot pass. This script only RUNS the pre-built binary; it never compiles.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

MAYHEM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$MAYHEM_DIR/.." && pwd)"
: "${OUT:=/mayhem}"

# Mayhem's runtime ASAN_OPTIONS is not in scope here; leaks in the one-shot oracle are irrelevant.
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

ORACLE="$OUT/inchi_golden_test"
FIXTURE="$REPO_ROOT/INCHI-1-TEST/tests/test_unit/fixtures/caffeine.mol"

# emit_ctrf <tool> <passed> <failed> [skipped]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}"
  local tests=$(( passed + failed + skipped ))
  cat > "${CTRF_REPORT:-$REPO_ROOT/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests, "passed": $passed, "failed": $failed,
      "pending": 0, "skipped": $skipped, "other": 0
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":0,"skipped":%d,"other":0}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$skipped"
  [ "$failed" -eq 0 ]
}

if [ ! -x "$ORACLE" ]; then
  echo "missing $ORACLE — run mayhem/build.sh first" >&2
  emit_ctrf "inchi-golden" 0 1 0; exit 2
fi
if [ ! -f "$FIXTURE" ]; then
  echo "missing fixture $FIXTURE" >&2
  emit_ctrf "inchi-golden" 0 1 0; exit 2
fi

echo "=== running inchi golden-roundtrip oracle ==="
out="$("$ORACLE" "$FIXTURE" 2>&1)"; rc=$?
echo "$out"

# The oracle prints one PASS/FAIL line per check (2 checks: mol2inchi, inchi2key).
PASS=$(printf '%s\n' "$out" | grep -c '^PASS ')
FAIL=$(printf '%s\n' "$out" | grep -c '^FAIL ')
: "${PASS:=0}" "${FAIL:=0}"

# If the binary aborted (sanitizer) before printing both lines, force a failure.
if [ "$rc" -ne 0 ] && [ "$FAIL" -eq 0 ]; then
  FAIL=$(( 2 - PASS )); [ "$FAIL" -lt 1 ] && FAIL=1
fi

emit_ctrf "inchi-golden" "$PASS" "$FAIL" 0
