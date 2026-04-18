{
  description = "Linera artifacts — deployment charts, docker compose, tooling.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          # Everything the Makefile / Justfile targets invoke, pinned via
          # nixpkgs. `direnv allow` + the root .envrc activates this
          # devshell in every subdirectory automatically.
          packages = with pkgs; [
            # Kubernetes / Helm tooling
            kubernetes-helm
            kubectl
            kind
            kubeconform
            chart-testing       # ct lint / ct install
            helm-docs

            # Container / compose tooling
            docker-compose
            hadolint

            # CI lint tools (match versions in .github/workflows/lint.yaml)
            yamllint
            shellcheck
            act

            # Release tooling
            cosign

            # Supply-chain helpers
            jq
            yq-go
            curl
            wget

            # Docs (`make docs-serve` bootstraps mkdocs in a local venv).
            python3

            # Task runners (ship both — some people prefer Make,
            # others Just; the two targets are kept in sync).
            gnumake
            just

            # charm.sh — optional TUI niceness used by `make menu` /
            # `just menu` and by `make view` / `just view`. The recipes
            # fall back to plain output if these are absent, so the
            # repo still works for users outside the nix devshell.
            gum
            glow
          ];

          shellHook = ''
            # helm-unittest isn't a standalone binary — install the
            # helm plugin on first shell activation so `helm unittest`
            # works immediately. Idempotent: helm prints "already
            # installed" on subsequent runs.
            if ! helm plugin list 2>/dev/null | grep -q '^unittest'; then
              echo "Installing helm-unittest plugin (one-time)…"
              helm plugin install https://github.com/helm-unittest/helm-unittest --version v0.8.1 \
                || true
            fi

            echo "linera-io/linera-artifacts devshell ready."
            echo "Run 'make help' or 'just --list' for available tasks."
          '';
        };
      });
}
