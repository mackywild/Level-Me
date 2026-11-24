#!/usr/bin/env bash
# Sign a build APK with the configured release key and publish only after verification.
set -euo pipefail
umask 077
if [[ $# != 2 ]]; then echo "Usage: sign_release_apk.sh INPUT OUTPUT" >&2; exit 2; fi
input="$1"
output="$2"
[[ -f "$input" && "$input" != "$output" && ! -e "$output" ]] || { echo "Invalid input/output APK paths" >&2; exit 2; }
: "${ANDROID_KEYSTORE_BASE64:?Missing keystore secret}"
: "${ANDROID_KEYSTORE_PASSWORD:?Missing keystore password}"
: "${ANDROID_KEY_ALIAS:?Missing key alias}"
: "${ANDROID_KEY_PASSWORD:?Missing key password}"
: "${ANDROID_CERT_SHA256:?Missing expected certificate fingerprint}"
expected="$(printf '%s' "$ANDROID_CERT_SHA256" | tr -d '[:space:]:' | tr '[:upper:]' '[:lower:]')"
[[ "$expected" =~ ^[a-f0-9]{64}$ ]] || { echo "Invalid expected SHA-256 fingerprint" >&2; exit 2; }
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[[ -d "$sdk/build-tools" ]] || { echo "Android build-tools unavailable" >&2; exit 2; }
apksigner="$(find "$sdk/build-tools" -name apksigner -type f | sort -V | tail -n 1)"
[[ -x "$apksigner" ]] || { echo "apksigner unavailable" >&2; exit 2; }
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64 --decode > "$tmp/release.p12"
unset ANDROID_KEYSTORE_BASE64
"$apksigner" sign --ks "$tmp/release.p12" --ks-type PKCS12 --ks-key-alias "$ANDROID_KEY_ALIAS" \
  --ks-pass env:ANDROID_KEYSTORE_PASSWORD --key-pass env:ANDROID_KEY_PASSWORD \
  --out "$tmp/signed.apk" "$input"
report="$("$apksigner" verify --print-certs "$tmp/signed.apk")"
printf '%s\n' "$report"
actual="$(printf '%s\n' "$report" | sed -nE 's/^.*certificate SHA-256 digest:[[:space:]]*([[:xdigit:]:]+)[[:space:]]*$/\1/p' | tr -d ':' | tr '[:upper:]' '[:lower:]' | sort -u)"
[[ "$actual" == "$expected" ]] || { echo "Release certificate mismatch; APK NOT published" >&2; exit 1; }
mkdir -p "$(dirname "$output")"
mv -- "$tmp/signed.apk" "$output"
echo "Release APK certificate verified."
