#!/usr/bin/env bash
# Retry only transient Maven HTTP 429 or damaged Android SDK/NDK download responses.
# Never mask Dart/Kotlin/Java compilation errors.
set -euo pipefail
if (( $# == 0 )); then
  echo 'Usage: ci_retry_gradle_429.sh <build command...>' >&2
  exit 2
fi
attempt=1
while :; do
  output="$(mktemp)"
  if "$@" 2>&1 | tee "$output"; then
    rm -f "$output"
    exit 0
  fi
  if (( attempt >= 3 )) || ! grep -Eiq '(HTTP[[:space:]]*429|status code 429|Too Many Requests|Error reading Zip content from a SeekableByteChannel)' "$output"; then
    rm -f "$output"
    exit 1
  fi
  rm -f "$output"
  delay="${NCA_GRADLE_RETRY_DELAY:-40}"
  if [[ ! "$delay" =~ ^[0-9]+$ ]] || (( delay > 90 )); then
    echo 'Invalid NCA_GRADLE_RETRY_DELAY' >&2
    exit 2
  fi
  echo "Transient Gradle dependency or Android NDK download failure; retrying build after backoff (attempt $attempt of 3)."
  sleep "$((delay * attempt))"
  attempt=$((attempt + 1))
done
