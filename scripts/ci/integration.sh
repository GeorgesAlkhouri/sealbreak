#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ "$#" -ne 2 ]]; then
  echo "usage: $0 <openbao|vault> <version>" >&2
  exit 64
fi

server="$1"
version="$2"
temp_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
work_dir="$(mktemp -d "$temp_root/sealbreak-integration.XXXXXX")"
bin_dir="$work_dir/bin"
tls_dir="$work_dir/tls"
data_dir="$work_dir/data"
server_log="$work_dir/server.log"
server_pid=""
ca_fingerprint=""

cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi

  if [[ -n "$ca_fingerprint" ]]; then
    sudo security delete-certificate -Z "$ca_fingerprint" /Library/Keychains/System.keychain >/dev/null 2>&1 || true
  fi

  rm -rf "$work_dir"
}
trap cleanup EXIT

mkdir -p "$bin_dir" "$tls_dir" "$data_dir"

case "$(uname -m)" in
  arm64)
    arch="arm64"
    ;;
  x86_64)
    arch="amd64"
    ;;
  *)
    echo "unsupported macOS architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

download() {
  curl --fail --location --retry 3 --retry-all-errors --silent --show-error "$1" --output "$2"
}

verify_checksum() {
  local checksum_file="$1"
  local archive_name="$2"
  local expected
  local actual

  expected="$(awk -v name="$archive_name" '$2 == name || $2 == "*" name { print $1; exit }' "$checksum_file")"
  actual="$(shasum -a 256 "$work_dir/$archive_name" | awk '{ print $1 }')"

  if [[ -z "$expected" || "$actual" != "$expected" ]]; then
    echo "checksum verification failed for $archive_name" >&2
    exit 1
  fi
}

case "$server" in
  openbao)
    archive_name="openbao_${version}_darwin_${arch}.tar.gz"
    archive_path="$work_dir/$archive_name"
    checksum_path="$work_dir/checksums.txt"
    release_base="https://github.com/openbao/openbao/releases/download/v${version}"

    download "$release_base/$archive_name" "$archive_path"
    download "$release_base/checksums.txt" "$checksum_path"
    verify_checksum "$checksum_path" "$archive_name"

    tar -xzf "$archive_path" -C "$bin_dir"
    server_bin="$bin_dir/bao"
    ;;
  vault)
    archive_name="vault_${version}_darwin_${arch}.zip"
    archive_path="$work_dir/$archive_name"
    checksum_path="$work_dir/vault_${version}_SHA256SUMS"
    release_base="https://releases.hashicorp.com/vault/${version}"

    download "$release_base/$archive_name" "$archive_path"
    download "$release_base/vault_${version}_SHA256SUMS" "$checksum_path"
    verify_checksum "$checksum_path" "$archive_name"

    unzip -q "$archive_path" -d "$bin_dir"
    server_bin="$bin_dir/vault"
    ;;
  *)
    echo "unsupported integration server: $server" >&2
    exit 64
    ;;
esac

test -x "$server_bin"

ca_cn="Sealbreak CI Test CA ${GITHUB_RUN_ID:-$}"

cat >"$tls_dir/ca.cnf" <<EOF
[req]
distinguished_name = distinguished_name
x509_extensions = v3_ca
prompt = no

[distinguished_name]
CN = $ca_cn

[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 1 -config "$tls_dir/ca.cnf" -keyout "$tls_dir/ca.key" -out "$tls_dir/ca.crt" >/dev/null 2>&1
openssl req -new -newkey rsa:2048 -sha256 -nodes -subj "/CN=localhost" -keyout "$tls_dir/server.key" -out "$tls_dir/server.csr" >/dev/null 2>&1

cat >"$tls_dir/server.ext" <<'EOF'
basicConstraints=critical,CA:FALSE
subjectAltName=DNS:localhost,IP:127.0.0.1
extendedKeyUsage=serverAuth
keyUsage=digitalSignature,keyEncipherment
EOF

openssl x509 -req -sha256 -days 1 -in "$tls_dir/server.csr" -CA "$tls_dir/ca.crt" -CAkey "$tls_dir/ca.key" -CAcreateserial -extfile "$tls_dir/server.ext" -out "$tls_dir/server.crt" >/dev/null 2>&1

ca_fingerprint="$(openssl x509 -in "$tls_dir/ca.crt" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"

sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$tls_dir/ca.crt"
security verify-cert -c "$tls_dir/server.crt" -p ssl -s localhost -q

cat >"$work_dir/server.hcl" <<EOF
ui = false
disable_mlock = true

storage "file" {
  path = "$data_dir"
}

listener "tcp" {
  address       = "127.0.0.1:8200"
  tls_cert_file = "$tls_dir/server.crt"
  tls_key_file  = "$tls_dir/server.key"
}

api_addr = "https://localhost:8200"
EOF

"$server_bin" server -config="$work_dir/server.hcl" >"$server_log" 2>&1 &
server_pid="$!"

ready=false
for _ in {1..30}; do
  if ! kill -0 "$server_pid" >/dev/null 2>&1; then
    echo "$server exited before becoming ready" >&2
    cat "$server_log" >&2
    exit 1
  fi

  status="$(curl --silent --output /dev/null --write-out '%{http_code}' --cacert "$tls_dir/ca.crt" https://localhost:8200/v1/sys/health || true)"
  if [[ "$status" == "501" ]]; then
    ready=true
    break
  fi

  sleep 1
done

if [[ "$ready" != "true" ]]; then
  echo "$server did not reach the expected uninitialized health state" >&2
  cat "$server_log" >&2
  exit 1
fi

init_json="$work_dir/init.json"
curl --fail-with-body --silent --show-error --cacert "$tls_dir/ca.crt" --header "Content-Type: application/json" --request POST --data '{"secret_shares":3,"secret_threshold":2}' https://localhost:8200/v1/sys/init --output "$init_json"

first_share="$(jq -er '.keys_base64[0]' "$init_json")"
second_share="$(jq -er '.keys_base64[1]' "$init_json")"
root_token="$(jq -er '.root_token' "$init_json")"

if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  echo "::add-mask::$first_share"
  echo "::add-mask::$second_share"
  echo "::add-mask::$root_token"
fi

submit_fixture_share() {
  jq -nc --arg key "$1" '{key:$key}' |
    curl       --fail-with-body       --silent       --show-error       --cacert "$tls_dir/ca.crt"       --header "Content-Type: application/json"       --request POST       --data-binary @-       https://localhost:8200/v1/sys/unseal       >/dev/null
}

# Product help/OpenAPI is not available while the server is sealed. Bring the
# fixture up only for product detection; the Swift test seals it again before
# exercising the complete Shamir progression through SealServerClient.
submit_fixture_share "$first_share"
submit_fixture_share "$second_share"

health_status="$(
  curl     --silent     --output /dev/null     --write-out '%{http_code}'     --cacert "$tls_dir/ca.crt"     https://localhost:8200/v1/sys/health
)"
if [[ "$health_status" != "200" ]]; then
  echo "$server did not reach the expected unsealed health state" >&2
  cat "$server_log" >&2
  exit 1
fi

env   SEALBREAK_INTEGRATION_SERVER_URL="https://localhost:8200"   SEALBREAK_INTEGRATION_SERVER_PRODUCT="$server"   SEALBREAK_INTEGRATION_SHARE_1="$first_share"   SEALBREAK_INTEGRATION_SHARE_2="$second_share"   SEALBREAK_INTEGRATION_ROOT_TOKEN="$root_token"   swift test     --filter SealbreakIntegrationTests.SealServerIntegrationTests     -Xswiftc -warnings-as-errors
