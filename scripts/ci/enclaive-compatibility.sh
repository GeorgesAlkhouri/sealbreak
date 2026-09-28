#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ "$#" -ne 1 ]]; then
  echo "usage: $0 <https://disposable-enclaive-vault-origin>" >&2
  echo "The target must be an uninitialized disposable instance. This probe initializes and unseals it." >&2
  exit 64
fi

base_url="${1%/}"
case "$base_url" in
  https://*)
    ;;
  *)
    echo "the compatibility target must use HTTPS" >&2
    exit 64
    ;;
esac

if [[ -n "${SEALBREAK_COMPAT_CA_CERT:-}" && ! -f "$SEALBREAK_COMPAT_CA_CERT" ]]; then
  echo "SEALBREAK_COMPAT_CA_CERT does not point to a readable CA certificate" >&2
  exit 64
fi

temp_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
work_dir="$(mktemp -d "$temp_root/sealbreak-enclaive-compat.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

curl_common=(
  --silent
  --show-error
  --connect-timeout 10
  --max-time 30
  --proto '=https'
  --tlsv1.2
  --header 'Accept: application/json'
)

if [[ -n "${SEALBREAK_COMPAT_CA_CERT:-}" ]]; then
  curl_common+=(--cacert "$SEALBREAK_COMPAT_CA_CERT")
fi

request_json() {
  local method="$1"
  local path="$2"
  local payload="${3:-}"
  local headers_file
  local body_file
  local status
  local body_size

  headers_file="$(mktemp "$work_dir/headers.XXXXXX")"
  body_file="$(mktemp "$work_dir/body.XXXXXX")"

  local -a request_args=(
    "${curl_common[@]}"
    --request "$method"
    --dump-header "$headers_file"
    --output "$body_file"
    --write-out '%{http_code}'
  )

  if [[ -n "$payload" ]]; then
    request_args+=(
      --header 'Content-Type: application/json'
      --data-binary '@-'
    )
    if ! status="$(printf '%s' "$payload" | curl "${request_args[@]}" "$base_url$path")"; then
      echo "$method $path failed at the transport layer" >&2
      exit 1
    fi
  elif ! status="$(curl "${request_args[@]}" "$base_url$path")"; then
    echo "$method $path failed at the transport layer" >&2
    exit 1
  fi

  if [[ "$status" != "200" ]]; then
    echo "$method $path returned HTTP $status; refusing to continue" >&2
    exit 1
  fi

  if ! grep -Eiq '^content-type:[[:space:]]*application/json([;[:space:]]|$)' "$headers_file"; then
    echo "$method $path did not return application/json" >&2
    exit 1
  fi

  body_size="$(wc -c <"$body_file" | tr -d '[:space:]')"
  if (( body_size > 65536 )); then
    echo "$method $path returned more than Sealbreak's 65536-byte response limit" >&2
    exit 1
  fi

  if ! jq -e . "$body_file" >/dev/null; then
    echo "$method $path returned invalid JSON" >&2
    exit 1
  fi

  cat "$body_file"
}

echo "Checking disposable enclaive Vault target: $base_url"

init_status="$(request_json GET '/v1/sys/init')"
if ! jq -e '.initialized == false' <<<"$init_status" >/dev/null; then
  echo "target is already initialized; refusing to alter an existing Vault" >&2
  exit 1
fi

init_response="$(request_json POST '/v1/sys/init' '{"secret_shares":3,"secret_threshold":2}')"
first_share="$(jq -er '.keys_base64[0]' <<<"$init_response")"
second_share="$(jq -er '.keys_base64[1]' <<<"$init_response")"

if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  echo "::add-mask::$first_share"
  echo "::add-mask::$second_share"
fi

assert_status() {
  local json="$1"
  local sealed="$2"
  local progress="$3"

  jq -e \
    --argjson sealed "$sealed" \
    --argjson progress "$progress" \
    '
      .initialized == true and
      .type == "shamir" and
      .sealed == $sealed and
      .n == 3 and
      .t == 2 and
      .progress == $progress and
      (.migration != true) and
      (.recovery_seal != true)
    ' <<<"$json" >/dev/null
}

initial_status="$(request_json GET '/v1/sys/seal-status')"
if ! assert_status "$initial_status" true 0; then
  echo "initial /sys/seal-status response is not compatible with Sealbreak's Shamir contract" >&2
  exit 1
fi

help_response="$(request_json GET '/v1/sys/seal-status?help=1')"
help_title="$(jq -r '.openapi.info.title // ""' <<<"$help_response")"

case "$help_title" in
  'HashiCorp Vault API')
    detected_product='Vault'
    ;;
  'OpenBao API')
    detected_product='OpenBao'
    ;;
  *)
    detected_product='Generic'
    ;;
esac

first_payload="$(printf '%s' "$first_share" | jq -Rs '{key: .}')"
first_response="$(request_json POST '/v1/sys/unseal' "$first_payload")"
if ! assert_status "$first_response" true 1; then
  echo "first /sys/unseal response is not compatible with Sealbreak's Shamir contract" >&2
  exit 1
fi

second_payload="$(printf '%s' "$second_share" | jq -Rs '{key: .}')"
second_response="$(request_json POST '/v1/sys/unseal' "$second_payload")"
if ! assert_status "$second_response" false 0; then
  echo "second /sys/unseal response is not compatible with Sealbreak's Shamir contract" >&2
  exit 1
fi

echo "enclaive Vault Shamir compatibility probe passed"
echo "Sealbreak product detection: $detected_product"
if [[ -n "$help_title" ]]; then
  echo "OpenAPI title: $help_title"
else
  echo "OpenAPI title: <missing>"
fi
