#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/fake-build" <<'SH'
#!/usr/bin/env bash
count="$(cat "$NCA_TEST_COUNTER")"
count=$((count+1))
echo "$count" > "$NCA_TEST_COUNTER"
if [[ "${NCA_FAIL_TYPE:-429}" == 429 ]] && (( count == 1 )); then
  echo 'Received status code 429 from server: Too Many Requests' >&2
  exit 1
fi
if [[ "${NCA_FAIL_TYPE:-429}" == ndk ]] && (( count == 1 )); then
  echo 'Warning: An error occurred while preparing SDK package NDK: Error reading Zip content from a SeekableByteChannel.' >&2
  exit 1
fi
if [[ "${NCA_FAIL_TYPE:-429}" == compile ]]; then
  echo 'Compilation error' >&2
  exit 1
fi
exit 0
SH
chmod +x "$scratch/fake-build"
echo 0 > "$scratch/count"
NCA_TEST_COUNTER="$scratch/count" NCA_GRADLE_RETRY_DELAY=0 \
  bash "$root/ci_retry_gradle_429.sh" "$scratch/fake-build"
test "$(cat "$scratch/count")" -eq 2
echo 0 > "$scratch/count"
NCA_TEST_COUNTER="$scratch/count" NCA_FAIL_TYPE=ndk NCA_GRADLE_RETRY_DELAY=0 \
  bash "$root/ci_retry_gradle_429.sh" "$scratch/fake-build"
test "$(cat "$scratch/count")" -eq 2
echo 0 > "$scratch/count"
if NCA_TEST_COUNTER="$scratch/count" NCA_FAIL_TYPE=compile NCA_GRADLE_RETRY_DELAY=0 \
  bash "$root/ci_retry_gradle_429.sh" "$scratch/fake-build"; then
  echo 'Non-network compile errors must fail.' >&2
  exit 1
fi
test "$(cat "$scratch/count")" -eq 1
echo 'Gradle 429 retry behavior verified.'
