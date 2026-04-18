#!/usr/bin/env bash
#
# install-prereqs.sh
#
# Install the operators the linera-validator-stack umbrella chart
# depends on but does NOT bundle: scylla-operator (always) and,
# optionally, cert-manager (needed if you use the chart's gateway
# integration with automatic TLS).
#
# Usage: ./install-prereqs.sh [OPTIONS]
#
# Options:
#   --skip-scylla-operator    Don't install scylla-operator.
#   --install-cert-manager    Also install cert-manager.
#   --scylla-op-version VER   scylla-operator chart version (default: 1.20.2).
#   --cert-mgr-version VER    cert-manager version (default: v1.20.2).
#   --dry-run                 Print what would happen; don't actually install.
#   --help, -h                Show this message.
#
# Prerequisites:
#   - helm 3.8+
#   - kubectl pointing at the target cluster
#
# The script is idempotent: re-running it upgrades in place.

set -euo pipefail

readonly DEFAULT_SCYLLA_OP_VERSION="1.20.2"
# 1.18+ ships the cert-manager / Gateway API shim ON by default, so
# Certificate resources auto-materialise from the
# `cert-manager.io/cluster-issuer` annotation on Gateway listeners.
readonly DEFAULT_CERT_MGR_VERSION="v1.20.2"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log() {
    local level="$1"; shift
    case "$level" in
        ERROR)   echo -e "${RED}[ERROR]${NC} $*" >&2 ;;
        WARNING) echo -e "${YELLOW}[WARNING]${NC} $*" ;;
        INFO)    echo -e "${GREEN}[INFO]${NC} $*" ;;
    esac
}

die() {
    log ERROR "$*"
    exit 1
}

usage() {
    sed -n '3,25p' "$0" | sed 's/^# \{0,1\}//'
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

main() {
    local skip_scylla=0 install_certmgr=0
    local scylla_version="$DEFAULT_SCYLLA_OP_VERSION"
    local certmgr_version="$DEFAULT_CERT_MGR_VERSION"
    local dry_run=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-scylla-operator) skip_scylla=1; shift ;;
            --install-cert-manager) install_certmgr=1; shift ;;
            --scylla-op-version)    scylla_version="$2"; shift 2 ;;
            --cert-mgr-version)     certmgr_version="$2"; shift 2 ;;
            --dry-run)              dry_run=1; shift ;;
            --help|-h)              usage; exit 0 ;;
            *)                      die "Unknown option: $1" ;;
        esac
    done

    require_cmd helm
    require_cmd kubectl

    log INFO "=== Installing linera-validator-stack prerequisites ==="
    log INFO "Target cluster: $(kubectl config current-context)"
    [[ $dry_run -eq 1 ]] && log WARNING "DRY RUN — nothing will be installed"

    # cert-manager goes first: scylla-operator's helm chart references
    # cert-manager.io/v1 Certificate + Issuer at install time, so the
    # CRDs must already exist when scylla-operator's chart renders.
    if [[ $install_certmgr -eq 1 ]]; then
        log INFO "cert-manager ${certmgr_version} → namespace cert-manager"
        if [[ $dry_run -eq 0 ]]; then
            helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
            helm repo update jetstack
            # `--enable-gateway-api` turns on the gateway-shim controller
            # so a Certificate resource is auto-created from
            # `cert-manager.io/cluster-issuer` annotations on Gateway
            # listeners (cert-manager 1.18+ ships the shim, but it's
            # OFF by default until this flag is passed).
            helm upgrade --install cert-manager jetstack/cert-manager \
                --version "$certmgr_version" \
                --namespace cert-manager --create-namespace \
                --set crds.enabled=true \
                --set 'extraArgs[0]=--enable-gateway-api' \
                --wait --timeout 10m
        fi
    fi

    if [[ $skip_scylla -eq 0 ]]; then
        log INFO "scylla-operator v${scylla_version} → namespace scylla-operator"
        if [[ $dry_run -eq 0 ]]; then
            helm repo add scylla https://scylla-operator-charts.storage.googleapis.com/stable 2>/dev/null || true
            helm repo update scylla

            # Helm's default `--skip-crds=false` applies CRDs only at
            # first install, NOT on upgrade. scylla-operator minor
            # bumps routinely add new CRDs; without this step the
            # freshly-bumped operator silently fails to reconcile
            # ScyllaClusters (controllers log `failed to list <new CRD>`
            # and skip). Apply the chart's CRDs explicitly every time.
            local scylla_chart_dir
            scylla_chart_dir=$(mktemp -d)
            trap 'rm -rf "$scylla_chart_dir"' RETURN
            helm pull scylla/scylla-operator \
                --version "$scylla_version" \
                --destination "$scylla_chart_dir" --untar
            if [[ -d "$scylla_chart_dir/scylla-operator/crds" ]]; then
                log INFO "Applying scylla-operator CRDs (chart-bundled)"
                kubectl apply --server-side=true \
                    -f "$scylla_chart_dir/scylla-operator/crds/"
            fi

            helm upgrade --install scylla-operator scylla/scylla-operator \
                --version "$scylla_version" \
                --namespace scylla-operator --create-namespace \
                --wait --timeout 10m
        fi
    else
        log INFO "Skipping scylla-operator (--skip-scylla-operator)"
    fi

    log INFO "Done. You can now install linera-validator-stack:"
    log INFO "  helm install validator-1 oci://ghcr.io/linera-io/charts/linera-validator-stack \\"
    log INFO "    --namespace linera --create-namespace \\"
    log INFO "    -f my-values.yaml"
}

main "$@"
