#!/usr/bin/env bash
#
# End-to-end tests for scripts/deploy-validator.sh.
#
# These run the script for real — not under --dry-run — against a stubbed
# `docker` and assert the files it writes. --dry-run returns early from
# generate_validator_config, generate_validator_keys and build_env, so a
# dry-run smoke test cannot see a wrong image, a mangled .env or a bad
# validator-config.toml. That is the gap these tests close.
#
# Usage: tests/deploy-validator-test.sh
# No dependencies beyond bash, jq and the repo itself.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly REGISTRY="us-docker.pkg.dev/linera-io-dev/linera-public-registry"
readonly DEFAULT_TAG="testnet_conway_release"

failures=0
current_case=""

fail() {
    echo "  FAIL: $*" >&2
    failures=$((failures + 1))
}

start_case() {
    current_case="$1"
    echo "== $current_case"
}

assert_eq() {
    local what="$1" want="$2" got="$3"
    [ "$want" = "$got" ] || fail "$what: want '$want', got '$got'"
}

assert_contains() {
    local what="$1" needle="$2" file="$3"
    grep -qF -- "$needle" "$file" || fail "$what: '$needle' missing from $file"
}

# Each case gets a pristine copy of the repo plus a stub `docker` on PATH, so
# nothing reaches the network and no container starts.
new_sandbox() {
    local dir
    dir="$(mktemp -d)"
    # Copy tracked files from the WORKING TREE, not from HEAD — testing HEAD
    # would silently ignore the change you are trying to validate.
    ( cd "$REPO_ROOT" && git ls-files -z | tar -c --null -T - -f - ) | tar -x -C "$dir"
    mkdir -p "$dir/stub"
    cat > "$dir/stub/docker" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DOCKER_CALL_LOG:-/dev/null}"
exit 0
STUB
    chmod +x "$dir/stub/docker"
    # A pre-placed server.json makes key generation deterministic and offline:
    # the script reuses an existing key rather than shelling out to generate one.
    printf '%s\n' '{"validator":{"public_key":"02aabb","account_key":{"Ed25519":"ccdd"}}}' \
        > "$dir/docker/server.json"
    echo '{"placeholder":"genesis"}' > "$dir/docker/genesis.json"
    echo "$dir"
}

run_deploy() {
    local dir="$1"; shift
    ( cd "$dir" && PATH="$dir/stub:$PATH" ./scripts/deploy-validator.sh "$@" ) \
        > "$dir/stdout.log" 2> "$dir/stderr.log"
}

env_value() {
    local dir="$1" key="$2"
    sed -n "s/^${key}=//p" "$dir/docker/.env" | tail -1
}

# --- the documented one-command deploy -------------------------------------
start_case "default invocation writes a complete .env"
d="$(new_sandbox)"
run_deploy "$d" v.example.com ops@example.com --skip-genesis
assert_eq "DOMAIN"                 "v.example.com"    "$(env_value "$d" DOMAIN)"
assert_eq "ACME_EMAIL"             "ops@example.com"  "$(env_value "$d" ACME_EMAIL)"
assert_eq "VALIDATOR_NAME"         "v.example.com"    "$(env_value "$d" VALIDATOR_NAME)"
assert_eq "HOSTNAME"               "v.example.com"    "$(env_value "$d" HOSTNAME)"
assert_eq "NUM_SHARDS"             "4"                "$(env_value "$d" NUM_SHARDS)"
assert_eq "VALIDATOR_KEY"          "02aabb,00ccdd"    "$(env_value "$d" VALIDATOR_KEY)"
assert_eq "LINERA_VALIDATOR_IMAGE" "${REGISTRY}/linera-validator:${DEFAULT_TAG}" \
                                   "$(env_value "$d" LINERA_VALIDATOR_IMAGE)"
assert_eq "LINERA_CLIENT_IMAGE"    "${REGISTRY}/linera-client:${DEFAULT_TAG}" \
                                   "$(env_value "$d" LINERA_CLIENT_IMAGE)"
rm -rf "$d"

# --- validator-config.toml -------------------------------------------------
start_case "validator-config.toml addresses exactly the shards compose defines"
d="$(new_sandbox)"
compose_shards="$(grep -cE '^[[:space:]]+hostname: docker-shard-[0-9]+$' "$d/docker/docker-compose.yaml")"
run_deploy "$d" v.example.com ops@example.com --skip-genesis
toml="$d/docker/validator-config.toml"
assert_contains "host"    'host = "v.example.com"' "$toml"
assert_contains "shard 1" 'host = "docker-shard-1"' "$toml"
assert_contains "last shard" "host = \"docker-shard-${compose_shards}\"" "$toml"
assert_eq "shard count matches compose" "$compose_shards" "$(grep -c '^\[\[shards\]\]' "$toml")"
assert_eq "NUM_SHARDS matches compose"  "$compose_shards" "$(env_value "$d" NUM_SHARDS)"
# Every shard the config names must be a hostname compose actually provides.
while read -r shard_host; do
    grep -qE "^[[:space:]]+hostname: ${shard_host}$" "$d/docker/docker-compose.yaml" \
        || fail "config addresses ${shard_host}, which compose does not define"
done < <(sed -n 's/^host = "\(docker-shard-[0-9]*\)"$/\1/p' "$toml")
rm -rf "$d"

# --num-shards used to be accepted unchecked, writing a config that addressed
# containers the stack never creates.
start_case "--num-shards must match the compose shard count"
d="$(new_sandbox)"
compose_shards="$(grep -cE '^[[:space:]]+hostname: docker-shard-[0-9]+$' "$d/docker/docker-compose.yaml")"
if run_deploy "$d" v.example.com ops@example.com --skip-genesis --num-shards $((compose_shards + 4)); then
    fail "too many shards was accepted"
else
    assert_contains "error names both counts" "docker-compose.yaml defines ${compose_shards}" "$d/stderr.log"
fi
if run_deploy "$d" v.example.com ops@example.com --skip-genesis --num-shards $((compose_shards - 1)); then
    fail "too few shards was accepted"
fi
if run_deploy "$d" v.example.com ops@example.com --skip-genesis --num-shards 0; then
    fail "zero shards was accepted"
fi
if run_deploy "$d" v.example.com ops@example.com --skip-genesis --num-shards abc; then
    fail "non-numeric shard count was accepted"
fi
if ! run_deploy "$d" v.example.com ops@example.com --skip-genesis --num-shards "$compose_shards"; then
    fail "the matching shard count was rejected"
fi
rm -rf "$d"

# --- image selection -------------------------------------------------------
start_case "--image-tag applies to both images"
d="$(new_sandbox)"
run_deploy "$d" v.example.com ops@example.com --skip-genesis --image-tag v1.2.3
assert_eq "validator" "${REGISTRY}/linera-validator:v1.2.3" "$(env_value "$d" LINERA_VALIDATOR_IMAGE)"
assert_eq "client"    "${REGISTRY}/linera-client:v1.2.3"    "$(env_value "$d" LINERA_CLIENT_IMAGE)"
rm -rf "$d"

start_case "--validator-image / --client-image override independently"
d="$(new_sandbox)"
run_deploy "$d" v.example.com ops@example.com --skip-genesis --validator-image a/val:1
assert_eq "validator overridden" "a/val:1" "$(env_value "$d" LINERA_VALIDATOR_IMAGE)"
assert_eq "client still default" "${REGISTRY}/linera-client:${DEFAULT_TAG}" \
                                 "$(env_value "$d" LINERA_CLIENT_IMAGE)"
rm -rf "$d"

start_case "LINERA_VALIDATOR_IMAGE / LINERA_CLIENT_IMAGE env overrides"
d="$(new_sandbox)"
( cd "$d" && PATH="$d/stub:$PATH" LINERA_VALIDATOR_IMAGE=my/val:x LINERA_CLIENT_IMAGE=my/cli:y \
    ./scripts/deploy-validator.sh v.example.com ops@example.com --skip-genesis ) >/dev/null 2>&1
assert_eq "validator" "my/val:x" "$(env_value "$d" LINERA_VALIDATOR_IMAGE)"
assert_eq "client"    "my/cli:y" "$(env_value "$d" LINERA_CLIENT_IMAGE)"
rm -rf "$d"

# The validator image is the one carrying /linera-server, so key generation
# must run that image and never the client image.
start_case "key generation runs the validator image"
d="$(new_sandbox)"
rm -f "$d/docker/server.json"
( cd "$d" && PATH="$d/stub:$PATH" DOCKER_CALL_LOG="$d/docker-calls.log" \
    ./scripts/deploy-validator.sh v.example.com ops@example.com --skip-genesis \
    --validator-image THEVALIDATOR:1 --client-image THECLIENT:2 ) >/dev/null 2>&1
keygen="$(grep -m1 'linera-server generate' "$d/docker-calls.log" || true)"
[ -n "$keygen" ] || fail "no keygen docker run recorded"
case "$keygen" in
    *THEVALIDATOR:1*) ;;
    *) fail "keygen used the wrong image: $keygen" ;;
esac
case "$keygen" in
    *THECLIENT:2*) fail "keygen used the client image: $keygen" ;;
esac
rm -rf "$d"

# --- operator data preservation --------------------------------------------
# docs/DOCKER-COMPOSE.md promises re-running is safe and that tuning survives.
start_case "re-run preserves in-body tuning and updates managed keys"
d="$(new_sandbox)"
run_deploy "$d" v.example.com ops@example.com --skip-genesis
# Uncommenting a template tunable is the documented way to change a default.
sed -i -E 's|^#PROMETHEUS_OTLP_URL=.*|PROMETHEUS_OTLP_URL=https://otlp.example.com|' "$d/docker/.env"
run_deploy "$d" other.example.com ops2@example.com --skip-genesis --image-tag v9.9.9
assert_eq "operator value survives" "https://otlp.example.com" \
          "$(env_value "$d" PROMETHEUS_OTLP_URL)"
assert_eq "managed key updated" "other.example.com" "$(env_value "$d" DOMAIN)"
assert_eq "image updated" "${REGISTRY}/linera-validator:v9.9.9" \
          "$(env_value "$d" LINERA_VALIDATOR_IMAGE)"
assert_eq "DOMAIN not duplicated" "1" "$(grep -c '^DOMAIN=' "$d/docker/.env")"
rm -rf "$d"

# The metadata block is written last, so anything the operator appends sits
# after it. Stripping the old block must not take that content with it.
start_case "re-run preserves content appended after the metadata block"
d="$(new_sandbox)"
run_deploy "$d" v.example.com ops@example.com --skip-genesis
printf 'MY_LATE_TUNING=keepme\n' >> "$d/docker/.env"
run_deploy "$d" v.example.com ops@example.com --skip-genesis
assert_eq "appended value survives" "keepme" "$(env_value "$d" MY_LATE_TUNING)"
assert_eq "metadata block not duplicated" "1" \
          "$(grep -c '^# Deployment metadata' "$d/docker/.env")"
assert_eq "DEPLOYMENT_HOST not duplicated" "1" \
          "$(grep -c '^DEPLOYMENT_HOST=' "$d/docker/.env")"
rm -rf "$d"

# A hand-written .env need not contain every managed key; the ones it lacks
# must still be written rather than appended and then stripped.
start_case "managed keys absent from a hand-written .env are still written"
d="$(new_sandbox)"
printf 'DOMAIN=old.example.com\nMY_CUSTOM_TUNING=keepme\n' > "$d/docker/.env"
run_deploy "$d" v.example.com ops@example.com --skip-genesis
run_deploy "$d" v.example.com ops@example.com --skip-genesis
assert_eq "custom value survives" "keepme" "$(env_value "$d" MY_CUSTOM_TUNING)"
assert_eq "NUM_SHARDS written"    "4"      "$(env_value "$d" NUM_SHARDS)"
assert_eq "validator image written" "${REGISTRY}/linera-validator:${DEFAULT_TAG}" \
          "$(env_value "$d" LINERA_VALIDATOR_IMAGE)"
rm -rf "$d"

# --- retired interfaces fail loudly ----------------------------------------
start_case "stale single-image interfaces are rejected"
d="$(new_sandbox)"
if run_deploy "$d" v.example.com ops@example.com --skip-genesis --linera-image old/img:1; then
    fail "--linera-image was accepted"
else
    assert_contains "flag error message" "no longer used" "$d/stderr.log"
fi
if ( cd "$d" && PATH="$d/stub:$PATH" LINERA_IMAGE=x ./scripts/deploy-validator.sh \
        v.example.com ops@example.com --skip-genesis ) >/dev/null 2>"$d/stderr2.log"; then
    fail "LINERA_IMAGE was accepted"
else
    assert_contains "env error message" "no longer used" "$d/stderr2.log"
fi
rm -rf "$d"

# --- required arguments ----------------------------------------------------
start_case "missing required arguments fail"
d="$(new_sandbox)"
if run_deploy "$d" --skip-genesis; then fail "missing host/email was accepted"; fi
if run_deploy "$d" v.example.com --skip-genesis; then fail "missing email was accepted"; fi
if run_deploy "$d" 'not a host' ops@example.com --skip-genesis; then fail "invalid host accepted"; fi
if run_deploy "$d" v.example.com 'not-an-email' --skip-genesis; then fail "invalid email accepted"; fi
rm -rf "$d"

echo
if [ "$failures" -eq 0 ]; then
    echo "all deploy-validator tests passed"
else
    echo "$failures assertion(s) failed" >&2
    exit 1
fi
