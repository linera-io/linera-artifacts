# Linera artifacts task runner (Just flavour).
#
# Mirror of the Makefile — pick whichever tool you like. Run
# `just --list` for the full list of targets.
#
# The nix devshell (flake.nix + .envrc) already has every tool these
# recipes invoke on $PATH.

# --- knobs ------------------------------------------------------------------

charts          := "helm/linera-validator helm/linera-block-exporter helm/linera-validator-stack"
helm_docs_image := "jnorwood/helm-docs:v1.14.2"
crd_catalog     := "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main"

# --- default ----------------------------------------------------------------

# List every recipe.
default:
    @just --list

# --- lint & test ------------------------------------------------------------

# Run every lint check.
lint: yamllint shellcheck helm-lint hadolint

# Run yamllint --strict across the tree.
yamllint:
    yamllint --strict .

# Run shellcheck on every committed shell script.
shellcheck:
    shellcheck scripts/*.sh docker/*.sh

# Lint any Dockerfile in the repo (no-op when there aren't any).
hadolint:
    #!/usr/bin/env bash
    if find . -name Dockerfile -not -path '*/node_modules/*' | grep -q .; then
      find . -name Dockerfile -not -path '*/node_modules/*' -print0 | xargs -0 hadolint
    else
      echo "No Dockerfiles to lint."
    fi

# `helm dependency build` for any chart with dependencies.
helm-deps:
    #!/usr/bin/env bash
    for chart in {{charts}}; do
      if grep -q '^dependencies:' "$chart/Chart.yaml"; then
        helm dependency build "$chart"
      fi
    done

# helm lint every chart.
helm-lint: helm-deps
    #!/usr/bin/env bash
    set -euo pipefail
    for chart in {{charts}}; do
      echo "=== helm lint $chart ==="
      helm lint "$chart"
    done

# Run helm-unittest across every chart's tests/.
helm-unittest: helm-deps
    #!/usr/bin/env bash
    set -euo pipefail
    for chart in {{charts}}; do
      if [ -d "$chart/tests" ]; then
        echo "=== helm unittest $chart ==="
        helm unittest "$chart"
      fi
    done

# helm template + kubeconform on every chart, for the matrix of K8s versions.
kubeconform k8s_version="1.30.0": helm-deps
    #!/usr/bin/env bash
    set -euo pipefail
    SCHEMA_FLAGS=(-strict -summary
        -kubernetes-version "{{k8s_version}}"
        -schema-location default
        -schema-location "{{crd_catalog}}/{{{{.Group}}}}/{{{{.ResourceKind}}}}_{{{{.ResourceAPIVersion}}}}.json")
    helm template helm/linera-validator \
      --set image.repository=x --set image.tag=y \
      --set validator.serverConfigData=a --set validator.genesisConfigData=b \
      --set serviceMonitor.enabled=true \
      --set ingress.enabled=true \
      --set 'ingress.hosts[0].host=v.example.com' \
      --set 'ingress.hosts[0].paths[0].path=/' \
      --set 'ingress.hosts[0].paths[0].pathType=Prefix' \
      --set gateway.enabled=true \
      --set gateway.className=envoy \
      --set gateway.hostname=v.example.com \
      --set gateway.tlsSecretName=tls \
      | kubeconform "${SCHEMA_FLAGS[@]}"
    helm template helm/linera-block-exporter \
      --set image.repository=x --set image.tag=y \
      --set storage.uri=scylladb:tcp:scylla:9042 \
      --set 'destinations[0].kind=Indexer' \
      --set 'destinations[0].endpoint=indexer.svc' \
      --set 'destinations[0].port=8081' \
      --set 'destinations[0].tls=ClearText' \
      --set serviceMonitor.enabled=true \
      | kubeconform "${SCHEMA_FLAGS[@]}"
    helm template helm/linera-validator-stack \
      --set linera-validator.image.repository=x \
      --set linera-validator.image.tag=y \
      --set linera-validator.validator.existingSecret=s \
      | kubeconform "${SCHEMA_FLAGS[@]}"

# Run `ct lint` (chart-testing) against every chart.
ct-lint:
    ct lint --config ct.yaml --all

# `ct install` — spin up kind, install every chart, helm test, tear down.
ct-install: dev-kind
    ct install --config ct.yaml --all --helm-extra-set-args "--set linera-validator.validator.serverConfigData=stub --set linera-validator.validator.genesisConfigData=stub"

# Regenerate every chart README from its .gotmpl template.
helm-docs:
    docker run --rm -v "$PWD:/work" -w /work {{helm_docs_image}} --chart-search-root=helm

# Regenerate READMEs and fail if git diff is non-empty.
helm-docs-check: helm-docs
    #!/usr/bin/env bash
    git diff --exit-code -- helm/*/README.md || { echo "Chart README out of date"; exit 1; }

# Run every non-install test.
test: helm-unittest kubeconform

# --- docs (mkdocs — mirror of the GitHub Pages site) ------------------------

docs_venv        := ".docs-venv"
mkdocs_version   := "1.6.1"
material_version := "9.5.44"
pymdown_version  := "10.12"
# Pygments 2.20 trips pymdownx.highlight on every fenced block; 2.18 is safe.
pygments_version := "2.18.0"

# Ensure the docs venv exists with pinned versions. Idempotent.
_docs-venv:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -x "{{docs_venv}}/bin/mkdocs" ]; then
      python3 -m venv "{{docs_venv}}"
      "{{docs_venv}}/bin/pip" install --quiet --upgrade pip
      "{{docs_venv}}/bin/pip" install --quiet \
        "mkdocs=={{mkdocs_version}}" \
        "mkdocs-material=={{material_version}}" \
        "pymdown-extensions=={{pymdown_version}}" \
        "Pygments=={{pygments_version}}"
    fi

# Serve the MkDocs site locally at http://127.0.0.1:8000 with live reload.
docs-serve: _docs-venv
    {{docs_venv}}/bin/mkdocs serve

# Build the MkDocs site into ./site (strict — same as CI).
docs-build: _docs-venv
    {{docs_venv}}/bin/mkdocs build --strict

# Remove the docs venv and build output.
docs-clean:
    rm -rf {{docs_venv}} site

# --- release helpers --------------------------------------------------------

# `helm package` every chart into .release/.
package: helm-deps
    #!/usr/bin/env bash
    mkdir -p .release
    for chart in {{charts}}; do
      helm package "$chart" --destination .release
    done
    ls .release/

# Remove .release/.
clean-release:
    rm -rf .release

# --- CI-in-a-box ------------------------------------------------------------

# Run the whole lint workflow locally via act.
act:
    act -W .github/workflows/lint.yaml --rm

# List act jobs.
act-list:
    act -W .github/workflows/lint.yaml -l

# --- dev loop ---------------------------------------------------------------

kind_cluster := "linera-dev"
dev_namespace := "linera"

# Create the kind cluster if missing, point kubectl at it, ensure the
# linera namespace exists. Idempotent.
dev-kind:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! kind get clusters 2>/dev/null | grep -qx "{{kind_cluster}}"; then
      echo "Creating kind cluster {{kind_cluster}}…"
      kind create cluster --name "{{kind_cluster}}" --wait 60s
    fi
    kubectl config use-context "kind-{{kind_cluster}}"
    kubectl create namespace {{dev_namespace}} --dry-run=client -o yaml | kubectl apply -f -

# Ensure kind cluster + namespace exist, then devspace dev pinned to
# the linera namespace. --no-warn skips DevSpace's interactive
# "are you sure about this namespace" prompt — we already chose.
# Stays attached: log stream + port-forward in the foreground.
dev: dev-kind
    devspace dev --namespace {{dev_namespace}} --no-warn

# Detached version. devspace v6 has no --background, so we run
# `devspace deploy` (install only) and start a background kubectl
# port-forward for the proxy. Stop with `just dev-bg-stop`.
dev-bg: dev-kind
    #!/usr/bin/env bash
    set -euo pipefail
    devspace deploy --namespace {{dev_namespace}} --no-warn
    mkdir -p .devspace
    kubectl --context kind-{{kind_cluster}} --namespace {{dev_namespace}} \
      wait --for=condition=available --timeout=600s deployment --all 2>/dev/null || true
    nohup kubectl --context kind-{{kind_cluster}} --namespace {{dev_namespace}} \
      port-forward svc/validator-proxy 19100:19100 \
      > .devspace/port-forward.log 2>&1 &
    echo $! > .devspace/port-forward.pid
    echo "Port-forward 19100 → svc/validator-proxy (PID $(cat .devspace/port-forward.pid))"
    echo "Logs: kubectl --context kind-{{kind_cluster}} -n {{dev_namespace}} logs -f -l app.kubernetes.io/component=proxy"
    echo "Stop: just dev-bg-stop"

# Stop the background port-forward started by `just dev-bg`.
dev-bg-stop:
    #!/usr/bin/env bash
    if [ -f .devspace/port-forward.pid ]; then
      pid="$(cat .devspace/port-forward.pid)"
      kill "$pid" 2>/dev/null || true
      rm -f .devspace/port-forward.pid
      echo "Stopped port-forward (PID $pid)"
    else
      echo "No port-forward PID file found."
    fi

# Ensure kind cluster + namespace exist, then devspace deploy (no
# log stream / no port-forward / no background process).
dev-deploy: dev-kind
    devspace deploy --namespace {{dev_namespace}} --no-warn

# Uninstall chart, delete the namespace, delete the kind cluster.
dev-down:
    #!/usr/bin/env bash
    just dev-bg-stop 2>/dev/null || true
    devspace purge --namespace {{dev_namespace}} --no-warn || true
    kind delete cluster --name "{{kind_cluster}}" || true

# --- interactive (charm.sh — optional) --------------------------------------

# Interactive task chooser. Needs charmbracelet/gum; falls back to `just --list`.
menu:
    #!/usr/bin/env bash
    if command -v gum >/dev/null 2>&1; then
      choice=$(gum choose --header "Linera artifacts — pick a task" \
        lint test helm-docs helm-docs-check package act dev dev-down ct-lint kubeconform)
      [ -n "$choice" ] && just "$choice"
    else
      echo "gum not found — falling back to 'just --list'."
      echo "Install it via the nix devshell (flake.nix) or https://github.com/charmbracelet/gum"
      just --list
    fi

# Render a repo doc with charmbracelet/glow; falls back to cat.
view doc="README.md":
    #!/usr/bin/env bash
    if command -v glow >/dev/null 2>&1; then glow "{{doc}}"; else cat "{{doc}}"; fi
