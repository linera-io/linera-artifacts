#!/usr/bin/env bash
#
# deploy-validator.sh
#
# Bootstrap a Linera validator node on a single host using the
# docker-compose stack in this repository.
#
# Usage: ./deploy-validator.sh <host> <email> [OPTIONS]
#
# Arguments:
#   <host>           Hostname/domain for the validator (required, used by Caddy
#                    for ACME and as the public Linera endpoint).
#   <email>          Email address registered with Let's Encrypt (required).
#
# Options:
#   --skip-genesis      Don't download genesis.json — assume it's already in place.
#   --force-genesis     Re-download genesis.json even if a copy exists locally.
#   --image-tag TAG     Linera image tag (default: testnet_conway_release).
#   --validator-image REF
#                       Override the linera-validator image reference
#                       (registry/name:tag). Runs linera-server / linera-proxy
#                       and generates the validator key.
#   --client-image REF  Override the linera-client image reference. Runs the
#                       `linera` CLI that shard-init invokes.
#   --xfs-path PATH     Bind-mount this XFS directory as the ScyllaDB data dir.
#   --num-shards N      Number of shards in validator-config.toml (default: 4).
#                       Must match the number of shard-N services in
#                       docker-compose.yaml.
#   --with-alloy        Add Grafana Alloy + cAdvisor; push metrics/
#                       logs/traces to remote endpoints you set in
#                       .env (PROMETHEUS_OTLP_URL etc.). What Linera
#                       runs internally. Off by default.
#   --with-local-monitoring
#                       Add the on-box monitoring stack (Prometheus +
#                       Grafana + Loki + Tempo + alert rules + Alloy +
#                       cAdvisor). Heavy, opt-in only. Off by default.
#                       Composes cleanly with --with-alloy if you want
#                       both on-box dashboards AND remote forwarding.
#   --dry-run           Print actions without executing them.
#   --help, -h          Show this help message.
#
# Environment overrides (lowest precedence):
#   GENESIS_URL, GENESIS_BUCKET, GENESIS_PATH_PREFIX, ACME_EMAIL,
#   LINERA_VALIDATOR_IMAGE, LINERA_CLIENT_IMAGE, IMAGE_TAG, NUM_SHARDS,
#   SCYLLA_XFS_PATH

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT
readonly COMPOSE_DIR="${REPO_ROOT}/docker"

readonly DEFAULT_REGISTRY="us-docker.pkg.dev/linera-io-dev/linera-public-registry"
readonly DEFAULT_VALIDATOR_IMAGE_NAME="linera-validator"
readonly DEFAULT_CLIENT_IMAGE_NAME="linera-client"
readonly DEFAULT_IMAGE_TAG="testnet_conway_release"
readonly DEFAULT_GENESIS_BUCKET="https://storage.googleapis.com/linera-io-dev-public"
readonly DEFAULT_NETWORK="testnet-conway"
readonly DEFAULT_NUM_SHARDS=4

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log() {
    local level="$1"; shift
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    case "$level" in
        ERROR)   echo -e "${RED}[ERROR]${NC} ${ts} - $*" >&2 ;;
        WARNING) echo -e "${YELLOW}[WARNING]${NC} ${ts} - $*" ;;
        INFO)    echo -e "${GREEN}[INFO]${NC} ${ts} - $*" ;;
    esac
}

usage() {
    # Print the header block verbatim; stops at the first non-comment line so
    # adding an option can never silently truncate --help again.
    awk 'NR < 3 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

die() {
    log ERROR "$*"
    exit 1
}

validate_host() {
    local host="$1"
    [[ "$host" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]] \
        || die "Invalid hostname: ${host}"
}

validate_email() {
    local email="$1"
    [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] \
        || die "Invalid email: ${email}"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

# validator-config.toml addresses shards by the hostname compose gives them, so
# asking for more shards than the stack defines yields a config pointing at
# containers that will never exist — a validator that starts and then cannot
# reach half its shards. Counted from the compose file so the two cannot drift.
validate_num_shards() {
    local requested="$1"
    local compose="${COMPOSE_DIR}/docker-compose.yaml"
    [[ "$requested" =~ ^[1-9][0-9]*$ ]] || die "--num-shards must be a positive integer, got: ${requested}"
    [[ -f "$compose" ]] || die "Missing ${compose}"
    local available
    available="$(grep -cE '^[[:space:]]+hostname: docker-shard-[0-9]+$' "$compose")"
    if [[ "$requested" -ne "$available" ]]; then
        die "--num-shards is ${requested} but docker-compose.yaml defines ${available} shard services.
  They must match, or the validator will address shards that do not exist.
  Either pass --num-shards ${available}, or add/remove shard services in ${compose}."
    fi
}

# A validator opens many short-lived gRPC/DNS connections. A low
# netfilter conntrack limit fills up and the kernel silently drops
# packets (including DNS), surfacing as cross-chain failures. Heavily
# suggested host setting; non-fatal warning only.
check_conntrack() {
    local cur min=1048576
    cur="$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null \
        || cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 0)"
    if [[ "$cur" =~ ^[0-9]+$ ]] && (( cur < min )); then
        log WARNING "net.netfilter.nf_conntrack_max is ${cur} (recommended >= ${min})."
        log WARNING "Heavily suggested before running a validator:"
        log WARNING "  echo 'net.netfilter.nf_conntrack_max=${min}' | sudo tee /etc/sysctl.d/99-linera.conf && sudo sysctl --system"
    fi
}

download_genesis() {
    local url="$1" target="$2" force="$3"
    if [[ -f "$target" && "$force" != "1" ]]; then
        log INFO "Genesis already present at ${target}, skipping download (use --force-genesis to override)."
        return 0
    fi
    if [[ -f "$target" ]]; then
        local backup
        backup="${target}.backup.$(date +%Y%m%d-%H%M%S)"
        cp "$target" "$backup"
        log INFO "Backed up existing genesis to ${backup}"
    fi
    log INFO "Downloading genesis from ${url}"
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        log INFO "[DRY RUN] would wget -O ${target} ${url}"
        return 0
    fi
    require_cmd wget
    wget -q -O "$target" "$url" || die "Failed to download genesis"
    [[ -s "$target" ]] || die "Downloaded genesis is empty"
}

generate_validator_config() {
    local host="$1" num_shards="$2"
    local config="${COMPOSE_DIR}/validator-config.toml"
    log INFO "Generating ${config}"
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        log INFO "[DRY RUN] would write validator-config.toml for ${host} with ${num_shards} shards"
        return 0
    fi
    {
        cat <<EOF
server_config_path = "server.json"
host = "${host}"
port = 443

[external_protocol]
Grpc = "Tls"

[internal_protocol]
Grpc = "ClearText"

[[proxies]]
host = "proxy"
public_port = 443
private_port = 20100
metrics_port = 21100

EOF
        for i in $(seq 1 "$num_shards"); do
            cat <<EOF
[[shards]]
host = "docker-shard-${i}"
port = 19100
metrics_port = 21100

EOF
        done
    } > "$config"
}

extract_public_key_from_server_json() {
    # Reconstruct the canonical "<validator_pk>,<account_key>" string
    # that `linera-server generate` prints to stdout, from a stored
    # server.json. The two halves have different on-disk shapes:
    #
    #   validator.public_key  - Secp256k1PublicKey with a custom human-
    #                           readable Serialize that already emits hex
    #                           of the compressed key (33 bytes -> 66 hex
    #                           chars). Same string as Display => use as-is.
    #   validator.account_key - AccountPublicKey enum with the default
    #                           tagged serde repr ({"Ed25519":"<hex>"},
    #                           {"Secp256k1":"<hex>"}, {"EvmSecp256k1":...}).
    #                           Display / FromStr use hex(bcs::to_bytes),
    #                           i.e. <BCS discriminant byte><inner hex>.
    #                           Variant order in linera-base/src/crypto/mod.rs:
    #                             0 -> Ed25519, 1 -> Secp256k1, 2 -> EvmSecp256k1.
    #
    # Stdout = key, never errors so the caller can keep going.
    local f="$1"
    if ! command -v jq >/dev/null 2>&1; then
        echo "(jq not installed — see ${f})"
        return 0
    fi
    jq -r '
        def account_key_display:
          if type == "string"  then .
          elif .Ed25519        then "00" + .Ed25519
          elif .Secp256k1      then "01" + .Secp256k1
          elif .EvmSecp256k1   then "02" + .EvmSecp256k1
          else null end;
        if (.validator.public_key and .validator.account_key
            and (.validator.account_key | account_key_display)) then
            "\(.validator.public_key),\(.validator.account_key | account_key_display)"
        else
            (.validator.public_key
             // .validator.name
             // .public_key
             // .name
             // empty)
        end
    ' "$f" 2>/dev/null || true
}

generate_validator_keys() {
    # stdout is the public key — log only to stderr.
    local image="$1"
    local server_json="${COMPOSE_DIR}/server.json"
    if [[ -f "$server_json" ]]; then
        log INFO "Validator key already exists at ${server_json}, leaving it untouched." >&2
        log INFO "Remove it manually and re-run if you want to rotate keys." >&2
        local existing_key
        existing_key="$(extract_public_key_from_server_json "$server_json")"
        if [[ -n "$existing_key" ]]; then
            echo "$existing_key"
        else
            echo "(could not extract key — inspect ${server_json})"
        fi
        return 0
    fi
    log INFO "Generating validator keys with ${image}" >&2
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        log INFO "[DRY RUN] would docker run ${image} /linera-server generate" >&2
        echo "DRY_RUN_PUBLIC_KEY"
        return 0
    fi
    docker run --rm \
        -v "${COMPOSE_DIR}:/config" \
        -w /config \
        "$image" \
        /linera-server generate --validators validator-config.toml
}

build_env() {
    # validator_image / client_image come from main's scope.
    local host="$1" email="$2" genesis_url="$3" \
          genesis_bucket="$4" genesis_prefix="$5" public_key="$6" num_shards="$7"
    local template="${COMPOSE_DIR}/.env.production.template"
    local env_file="${COMPOSE_DIR}/.env"
    [[ -f "$template" ]] || die "Template missing: ${template}"
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        log INFO "[DRY RUN] would update or render .env"
        return 0
    fi

    # If a .env already exists, PRESERVE the operator's existing
    # values (especially OTLP push URLs, custom limits, secrets).
    # Just patch the few fields driven by this script's arguments.
    # If no .env exists, render fresh from the template.
    if [[ -f "$env_file" ]]; then
        local backup
        backup="${env_file}.backup.$(date +%Y%m%d-%H%M%S)"
        cp "$env_file" "$backup"
        log INFO "Backed up existing .env to ${backup} (existing values preserved)"
    else
        cp "$template" "$env_file"
        log INFO "Initialised .env from template"
    fi

    # Set / replace each script-driven field. `set_or_replace` handles
    # both "key absent" and "key present (commented or not)" cases, so
    # it's safe whether the .env came from the template or from an
    # operator's hand-edited file.
    set_or_replace() {
        local key="$1" value="$2"
        if grep -qE "^#?${key}=" "$env_file"; then
            sed -i -E "s|^#?${key}=.*|${key}=${value}|" "$env_file"
        else
            printf '%s=%s\n' "$key" "$value" >> "$env_file"
        fi
    }
    set_or_replace DOMAIN "$host"
    set_or_replace ACME_EMAIL "$email"
    set_or_replace GENESIS_URL "$genesis_url"
    set_or_replace GENESIS_BUCKET "$genesis_bucket"
    set_or_replace GENESIS_PATH_PREFIX "$genesis_prefix"
    set_or_replace VALIDATOR_KEY "$public_key"
    set_or_replace VALIDATOR_NAME "$host"
    set_or_replace HOSTNAME "$host"
    set_or_replace LINERA_VALIDATOR_IMAGE "$validator_image"
    set_or_replace LINERA_CLIENT_IMAGE "$client_image"
    set_or_replace NUM_SHARDS "$num_shards"

    # Refresh the deployment metadata block, stripping the previous one by the
    # lines it owns. Deleting through to end-of-file instead would take any
    # operator line that landed after it, since the block is always last.
    sed -i -E '/^# Deployment metadata \(generated by deploy-validator/d; /^DEPLOYMENT_(HOST|EMAIL|PUBLIC_KEY)=/d' "$env_file"
    cat >> "$env_file" <<EOF
# Deployment metadata (generated by deploy-validator.sh on $(date -Iseconds))
DEPLOYMENT_HOST=${host}
DEPLOYMENT_EMAIL=${email}
DEPLOYMENT_PUBLIC_KEY=${public_key}
EOF
    log INFO "Wrote ${env_file}"
}

main() {
    local host="" email=""
    local skip_genesis=0 force_genesis=0
    local image_tag="${IMAGE_TAG:-$DEFAULT_IMAGE_TAG}"
    # Two images since the upstream split: linera-validator runs
    # linera-server / linera-proxy, linera-client runs the `linera` CLI
    # that shard-init invokes.
    local validator_image="${LINERA_VALIDATOR_IMAGE:-}"
    local client_image="${LINERA_CLIENT_IMAGE:-}"
    if [ -n "${LINERA_IMAGE:-}" ]; then
        echo "ERROR: LINERA_IMAGE is set but is no longer used." >&2
        echo "  Use LINERA_VALIDATOR_IMAGE and LINERA_CLIENT_IMAGE instead." >&2
        exit 1
    fi
    local num_shards="${NUM_SHARDS:-$DEFAULT_NUM_SHARDS}"
    local xfs_path="${SCYLLA_XFS_PATH:-}"
    local with_alloy="${WITH_ALLOY:-0}"
    local with_local_monitoring="${WITH_LOCAL_MONITORING:-0}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-genesis)   skip_genesis=1; shift ;;
            --force-genesis)  force_genesis=1; shift ;;
            --image-tag)      image_tag="$2"; shift 2 ;;
            --validator-image) validator_image="$2"; shift 2 ;;
            --client-image)   client_image="$2"; shift 2 ;;
            --linera-image)   die "--linera-image is no longer used. Pass --validator-image and/or --client-image instead." ;;
            --xfs-path)       xfs_path="$2"; shift 2 ;;
            --num-shards)     num_shards="$2"; shift 2 ;;
            --with-alloy)     with_alloy=1; shift ;;
            --with-local-monitoring) with_local_monitoring=1; shift ;;
            --dry-run)        DRY_RUN=1; shift ;;
            --help|-h)        usage; exit 0 ;;
            -*)               die "Unknown option: $1" ;;
            *)
                if [[ -z "$host" ]]; then
                    host="$1"
                elif [[ -z "$email" ]]; then
                    email="$1"
                else
                    die "Unexpected argument: $1"
                fi
                shift
                ;;
        esac
    done

    [[ -n "$host" ]]  || { usage; die "host is required"; }
    [[ -n "$email" ]] || { usage; die "email is required"; }
    validate_host "$host"
    validate_email "$email"
    validate_num_shards "$num_shards"

    require_cmd docker
    docker compose version >/dev/null 2>&1 || die "Missing required command: docker compose"
    check_conntrack

    [[ $skip_genesis -eq 1 && $force_genesis -eq 1 ]] && \
        die "--skip-genesis and --force-genesis are mutually exclusive"

    # Defaulted after parsing, since --image-tag feeds both references.
    [ -n "$validator_image" ] || validator_image="${DEFAULT_REGISTRY}/${DEFAULT_VALIDATOR_IMAGE_NAME}:${image_tag}"
    [ -n "$client_image" ] || client_image="${DEFAULT_REGISTRY}/${DEFAULT_CLIENT_IMAGE_NAME}:${image_tag}"

    local genesis_bucket="${GENESIS_BUCKET:-$DEFAULT_GENESIS_BUCKET}"
    local genesis_prefix="${GENESIS_PATH_PREFIX:-$DEFAULT_NETWORK}"
    local genesis_url="${GENESIS_URL:-${genesis_bucket}/${genesis_prefix}/genesis.json}"

    log INFO "=== Linera validator deployment ==="
    log INFO "Host:           ${host}"
    log INFO "Email:          ${email}"
    log INFO "Validator image: ${validator_image}"
    log INFO "Client image:   ${client_image}"
    log INFO "Genesis URL:    ${genesis_url}"
    log INFO "Num shards:     ${num_shards}"
    [[ -n "$xfs_path" ]] && log INFO "Scylla XFS path: ${xfs_path}"

    mkdir -p "${COMPOSE_DIR}"

    if [[ $skip_genesis -eq 1 ]]; then
        [[ -s "${COMPOSE_DIR}/genesis.json" ]] || die "--skip-genesis requires an existing ${COMPOSE_DIR}/genesis.json"
        log INFO "Skipping genesis download (--skip-genesis)"
    else
        download_genesis "$genesis_url" "${COMPOSE_DIR}/genesis.json" "$force_genesis"
    fi

    generate_validator_config "$host" "$num_shards"

    local public_key
    public_key="$(generate_validator_keys "$validator_image")"

    build_env "$host" "$email" \
              "$genesis_url" "$genesis_bucket" "$genesis_prefix" \
              "$public_key" "$num_shards"

    if [[ -n "$xfs_path" ]]; then
        local override="${COMPOSE_DIR}/docker-compose.override.yml"
        log INFO "Generating ${override} (XFS bind mount: ${xfs_path}/scylla-data)"
        if [[ "${DRY_RUN:-0}" != "1" ]]; then
            mkdir -p "${xfs_path}/scylla-data"
            chown -R 999:999 "${xfs_path}/scylla-data" 2>/dev/null \
                || log WARNING "Could not chown ${xfs_path}/scylla-data to 999:999 — may need sudo"
            cat > "$override" <<EOF
# Generated by deploy-validator.sh on $(date -Iseconds)
services:
  scylla:
    volumes:
      - ${xfs_path}/scylla-data:/var/lib/scylla
EOF
        fi
    fi

    local -a compose_files=(-f docker-compose.yaml)
    local -a obs_summary=()
    if [[ $with_alloy -eq 1 ]]; then
        compose_files+=(-f docker-compose.alloy.yaml)
        obs_summary+=(alloy)
    fi
    if [[ $with_local_monitoring -eq 1 ]]; then
        compose_files+=(-f docker-compose.local-monitoring.yaml)
        obs_summary+=(local-monitoring)
    fi
    if [[ ${#obs_summary[@]} -eq 0 ]]; then
        log INFO "Observability: off (validator /metrics still exposed on :21100)"
    else
        log INFO "Observability: ${obs_summary[*]}"
    fi

    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        log INFO "[DRY RUN] would: cd ${COMPOSE_DIR} && docker compose ${compose_files[*]} up -d"
    else
        log INFO "Starting docker compose stack..."
        ( cd "$COMPOSE_DIR" && docker compose "${compose_files[@]}" up -d --wait )
    fi

    echo
    log INFO "=== Deployment complete ==="
    log INFO "Public key:        ${public_key}"
    log INFO "Validator URL:     https://${host}"
    echo
    log WARNING "Next steps for external validators:"
    log WARNING "  1. Save the public key above — you'll need it to register your validator."
    log WARNING "  2. Send your public key to the Linera network operators."
    log WARNING "  3. Watch logs: cd ${COMPOSE_DIR} && docker compose logs -f"
}

main "$@"
