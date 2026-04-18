# Linera artifacts task runner.
#
# This Makefile and the sibling Justfile expose the same targets;
# pick whichever you prefer.
#
# If you're using the nix devshell (`flake.nix` + `.envrc`), every tool
# these targets invoke is already on $PATH.
#
# Run `make help` for the full list.

SHELL := bash
.DEFAULT_GOAL := help

# --- knobs ------------------------------------------------------------------

CHARTS          := helm/linera-validator helm/linera-block-exporter helm/linera-validator-stack
HELM_DOCS_IMAGE := jnorwood/helm-docs:v1.14.2
K8S_VERSIONS    := 1.28.0 1.30.0
CRD_CATALOG     := https://raw.githubusercontent.com/datreeio/CRDs-catalog/main

# --- help -------------------------------------------------------------------

.PHONY: help
help: ## Show this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage: make \033[36m<target>\033[0m\n\nTargets:\n"} \
	/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 } \
	/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Lint & test

.PHONY: lint
lint: yamllint shellcheck helm-lint hadolint ## Run every lint check.

.PHONY: yamllint
yamllint: ## Run yamllint --strict across the tree.
	yamllint --strict .

.PHONY: shellcheck
shellcheck: ## Run shellcheck on every committed shell script.
	shellcheck scripts/*.sh docker/*.sh

.PHONY: hadolint
hadolint: ## Lint any Dockerfile in the repo (no-op when there aren't any).
	@if find . -name Dockerfile -not -path '*/node_modules/*' | grep -q .; then \
	  find . -name Dockerfile -not -path '*/node_modules/*' -print0 | xargs -0 hadolint; \
	else \
	  echo "No Dockerfiles to lint."; \
	fi

.PHONY: helm-lint
helm-lint: helm-deps ## helm lint every chart.
	@for chart in $(CHARTS); do \
	  echo "=== helm lint $$chart ==="; \
	  helm lint $$chart || exit 1; \
	done

.PHONY: helm-deps
helm-deps: ## `helm dependency build` for any chart with dependencies.
	@for chart in $(CHARTS); do \
	  if grep -q '^dependencies:' $$chart/Chart.yaml; then \
	    helm dependency build $$chart; \
	  fi; \
	done

.PHONY: helm-unittest
helm-unittest: helm-deps ## Run helm-unittest across every chart's tests/.
	@for chart in $(CHARTS); do \
	  if [ -d $$chart/tests ]; then \
	    echo "=== helm unittest $$chart ==="; \
	    helm unittest $$chart || exit 1; \
	  fi; \
	done

.PHONY: kubeconform
kubeconform: helm-deps ## helm template every chart and validate with kubeconform.
	@set -e; \
	for v in $(K8S_VERSIONS); do \
	  echo "=== kubeconform K8s $$v ==="; \
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
	    | kubeconform -strict -summary \
	        -kubernetes-version $$v \
	        -schema-location default \
	        -schema-location '$(CRD_CATALOG)/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'; \
	  helm template helm/linera-block-exporter \
	    --set image.repository=x --set image.tag=y \
	    --set storage.uri=scylladb:tcp:scylla:9042 \
	    --set 'destinations[0].kind=Indexer' \
	    --set 'destinations[0].endpoint=indexer.svc' \
	    --set 'destinations[0].port=8081' \
	    --set 'destinations[0].tls=ClearText' \
	    --set serviceMonitor.enabled=true \
	    | kubeconform -strict -summary \
	        -kubernetes-version $$v \
	        -schema-location default \
	        -schema-location '$(CRD_CATALOG)/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'; \
	  helm template helm/linera-validator-stack \
	    --set linera-validator.image.repository=x \
	    --set linera-validator.image.tag=y \
	    --set linera-validator.validator.existingSecret=s \
	    | kubeconform -strict -summary \
	        -kubernetes-version $$v \
	        -schema-location default \
	        -schema-location '$(CRD_CATALOG)/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'; \
	done

.PHONY: ct-lint
ct-lint: ## Run `ct lint` (chart-testing) against every chart.
	ct lint --config ct.yaml --all

.PHONY: ct-install
ct-install: dev-kind ## Run `ct install` — spin up kind, install every chart, run helm test, tear down.
	ct install --config ct.yaml --all --helm-extra-set-args "--set linera-validator.validator.serverConfigData=stub --set linera-validator.validator.genesisConfigData=stub"

.PHONY: helm-docs
helm-docs: ## Regenerate every chart README from its .gotmpl template.
	docker run --rm -v "$$PWD:/work" -w /work $(HELM_DOCS_IMAGE) --chart-search-root=helm

.PHONY: helm-docs-check
helm-docs-check: helm-docs ## Regenerate READMEs and fail if git diff is non-empty.
	@git diff --exit-code -- helm/*/README.md || { echo "Chart README out of date"; exit 1; }

.PHONY: test
test: helm-unittest kubeconform ## Run every non-install test.

##@ Docs (MkDocs — mirror of the GitHub Pages site)

DOCS_VENV        := .docs-venv
MKDOCS           := $(DOCS_VENV)/bin/mkdocs
MKDOCS_VERSION   := 1.6.1
MATERIAL_VERSION := 9.5.44
PYMDOWN_VERSION  := 10.12
# Pygments 2.20 triggers an AttributeError inside pymdownx.highlight on any
# fenced code block. 2.18 works with the pinned mkdocs-material above; bump
# together.
PYGMENTS_VERSION := 2.18.0

$(MKDOCS):
	python3 -m venv $(DOCS_VENV)
	$(DOCS_VENV)/bin/pip install --quiet --upgrade pip
	$(DOCS_VENV)/bin/pip install --quiet \
	  mkdocs==$(MKDOCS_VERSION) \
	  mkdocs-material==$(MATERIAL_VERSION) \
	  pymdown-extensions==$(PYMDOWN_VERSION) \
	  Pygments==$(PYGMENTS_VERSION)

.PHONY: docs-serve
docs-serve: $(MKDOCS) ## Serve the MkDocs site locally at http://127.0.0.1:8000 with live reload.
	$(MKDOCS) serve

.PHONY: docs-build
docs-build: $(MKDOCS) ## Build the MkDocs site into ./site (strict — same as CI).
	$(MKDOCS) build --strict

.PHONY: docs-clean
docs-clean: ## Remove the docs venv and build output.
	rm -rf $(DOCS_VENV) site

##@ Release helpers (manual — actual push is a GH workflow)

.PHONY: package
package: helm-deps ## `helm package` every chart into .release/.
	@mkdir -p .release
	@for chart in $(CHARTS); do \
	  helm package $$chart --destination .release; \
	done
	@ls .release/

.PHONY: clean-release
clean-release: ## Remove .release/.
	rm -rf .release

##@ CI-in-a-box

.PHONY: act
act: ## Run the whole lint workflow locally via act (matches GitHub Actions).
	act -W .github/workflows/lint.yaml --rm

.PHONY: act-list
act-list: ## List act jobs.
	act -W .github/workflows/lint.yaml -l

##@ Dev loop (devspace + kind)

KIND_CLUSTER ?= linera-dev
DEV_NAMESPACE ?= linera

.PHONY: dev-kind
dev-kind: ## Create the kind cluster + linera namespace and switch kubectl to it.
	@if ! kind get clusters 2>/dev/null | grep -qx "$(KIND_CLUSTER)"; then \
	  echo "Creating kind cluster $(KIND_CLUSTER)…"; \
	  kind create cluster --name "$(KIND_CLUSTER)" --wait 60s; \
	fi
	kubectl config use-context "kind-$(KIND_CLUSTER)"
	kubectl create namespace $(DEV_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

.PHONY: dev
dev: dev-kind ## Ensure kind cluster + namespace exist, then `devspace dev` (foreground; logs + port-forward attached).
	devspace dev --namespace $(DEV_NAMESPACE) --no-warn

.PHONY: dev-bg
dev-bg: dev-kind ## Same as `dev` but detached: `devspace deploy` + background kubectl port-forward.
	@devspace deploy --namespace $(DEV_NAMESPACE) --no-warn
	@mkdir -p .devspace
	@kubectl --context kind-$(KIND_CLUSTER) --namespace $(DEV_NAMESPACE) \
	  wait --for=condition=available --timeout=600s deployment --all 2>/dev/null || true
	@nohup kubectl --context kind-$(KIND_CLUSTER) --namespace $(DEV_NAMESPACE) \
	  port-forward svc/validator-proxy 19100:19100 \
	  > .devspace/port-forward.log 2>&1 & echo $$! > .devspace/port-forward.pid
	@echo "Port-forward 19100 → svc/validator-proxy (PID $$(cat .devspace/port-forward.pid))"
	@echo "Logs: kubectl --context kind-$(KIND_CLUSTER) -n $(DEV_NAMESPACE) logs -f -l app.kubernetes.io/component=proxy"
	@echo "Stop: make dev-bg-stop"

.PHONY: dev-bg-stop
dev-bg-stop: ## Stop the background port-forward started by `make dev-bg`.
	@if [ -f .devspace/port-forward.pid ]; then \
	  pid="$$(cat .devspace/port-forward.pid)"; \
	  kill "$$pid" 2>/dev/null || true; \
	  rm -f .devspace/port-forward.pid; \
	  echo "Stopped port-forward (PID $$pid)"; \
	else \
	  echo "No port-forward PID file found."; \
	fi

.PHONY: dev-deploy
dev-deploy: dev-kind ## Ensure kind cluster + namespace exist, then `devspace deploy` (no log stream / no port-forward).
	devspace deploy --namespace $(DEV_NAMESPACE) --no-warn

.PHONY: dev-down
dev-down: ## Stop port-forward, uninstall chart, delete the kind cluster.
	-$(MAKE) dev-bg-stop
	-devspace purge --namespace $(DEV_NAMESPACE) --no-warn
	-kind delete cluster --name "$(KIND_CLUSTER)"

##@ Interactive (charm.sh — optional)

.PHONY: menu
menu: ## Interactive task chooser (needs charmbracelet/gum; falls back to `make help`).
	@if command -v gum >/dev/null 2>&1; then \
	  choice=$$(gum choose --header "Linera artifacts — pick a task" \
	    lint test helm-docs helm-docs-check package act dev dev-down ct-lint kubeconform); \
	  [ -n "$$choice" ] && $(MAKE) $$choice; \
	else \
	  echo "gum not found — falling back to 'make help'."; \
	  echo "Install it via the nix devshell (flake.nix) or https://github.com/charmbracelet/gum"; \
	  $(MAKE) help; \
	fi

.PHONY: view
view: ## Render a repo doc with charmbracelet/glow (falls back to cat). Usage: make view DOC=docs/QUICKSTART.md
	@doc="$${DOC:-README.md}"; \
	if command -v glow >/dev/null 2>&1; then glow "$$doc"; else cat "$$doc"; fi

##@ Housekeeping

.PHONY: fmt-check
fmt-check: yamllint shellcheck ## Alias: run every formatter/linter in check-only mode.
