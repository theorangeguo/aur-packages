# AUR Packages Monorepo 📦

This repository contains my maintained Arch User Repository (AUR) packages. The entire build, verification, and publishing process is automated via GitHub Actions.

## 🚀 Packages Managed

| Package | Description | Status |
|---------|-------------|--------|
| [antigravity-tools-bin](https://aur.archlinux.org/packages/antigravity-tools-bin) | Professional Antigravity Account Manager & Switcher | ![Build Status](https://github.com/orange-guo/aur-packages/actions/workflows/aur-publish.yml/badge.svg) |
| [claude-code-stable-bin](https://aur.archlinux.org/packages/claude-code-stable-bin) | Claude Code terminal-based AI coding assistant (stable channel) | ![Build Status](https://github.com/orange-guo/aur-packages/actions/workflows/aur-publish.yml/badge.svg) |
| [cli-proxy-api-bin](https://aur.archlinux.org/packages/cli-proxy-api-bin) | Proxy server providing OpenAI/Gemini/Claude compatible API interfaces | ![Build Status](https://github.com/orange-guo/aur-packages/actions/workflows/aur-publish.yml/badge.svg) |
| [cpa-usage-keeper-bin](https://aur.archlinux.org/packages/cpa-usage-keeper-bin) | Standalone CLIProxyAPI usage persistence and dashboard service | ![Build Status](https://github.com/orange-guo/aur-packages/actions/workflows/aur-publish.yml/badge.svg) |
| [fingerprint-chromium-bin](https://aur.archlinux.org/packages/fingerprint-chromium-bin) | Fingerprint Chromium (Ungoogled Chromium with fingerprinting protection) | ![Build Status](https://github.com/orange-guo/aur-packages/actions/workflows/aur-publish.yml/badge.svg) |
| [vibe-kanban-bin](https://aur.archlinux.org/packages/vibe-kanban-bin) | AI-powered Kanban board | ![Build Status](https://github.com/orange-guo/aur-packages/actions/workflows/aur-publish.yml/badge.svg) |
| [wlroots0.20-vmwgfx](https://aur.archlinux.org/packages/wlroots0.20-vmwgfx) | wlroots 0.20 with a vmwgfx compatibility patch for VMware environments | ![Build Status](https://github.com/orange-guo/aur-packages/actions/workflows/aur-publish.yml/badge.svg) |
| [zellij-no-mouse-resize-bin](https://aur.archlinux.org/packages/zellij-no-mouse-resize-bin) | Zellij with advanced_mouse_actions also gating pane mouse resize | ![Build Status](https://github.com/orange-guo/aur-packages/actions/workflows/aur-publish.yml/badge.svg) |

## 🛠 Automation Workflow

The system uses a centralized manager script [`scripts/ci_manager.sh`](scripts/ci_manager.sh) to handle the entire lifecycle:

1.  **Discovery**: Automatically scans the repository for PackageSpec v1 definitions (`package.conf` files).
2.  **Resolve**: Fetches upstream versions and asset URLs.
3.  **Render**: Generates a temporary `PKGBUILD`, optional `.install`, and other packaging assets.
4.  **Build**: Verifies the package builds successfully in a clean environment.
5.  **Package Validation**: Installs the built package and runs package-level smoke checks.
6.  **Publish**: Pushes the rendered package contents to AUR only after package validation passes.

The package validation workflow and the publish workflow share the same smoke-check path, so scheduled AUR publishes are gated on the same package-level checks used in pull requests.

For a deeper explanation of the moving parts, see [docs/WORKFLOW.md](docs/WORKFLOW.md). For framework boundaries and package extension rules, see [docs/PACKAGE_FRAMEWORK.md](docs/PACKAGE_FRAMEWORK.md).

The publish workflow runs automatically **every 6 hours**. Package validation runs on pull requests, pushes to `main`, and manual dispatches. The binary-release producer runs on schedule, manual dispatch, and non-`main` branch pushes that touch relevant files.

## 💻 Local Usage

You can use the `ci_manager.sh` script to test changes locally. This script handles dependency installation and user permission switching automatically.

### Prerequisites
*   Arch Linux based system (or container)
*   `sudo` privileges
*   Docker or Podman for local `run-test`

### Commands

**1. Install Dependencies:**
```bash
sudo ./scripts/ci_manager.sh install
sudo ./scripts/ci_manager.sh setup-user
```

**2. Run Publish Path (Dry Run):**
```bash
# Syntax: ./scripts/ci_manager.sh run-publish <pkgname-or-path> [flags]
./scripts/ci_manager.sh run-publish antigravity-tools-bin --dry-run
```

**3. Run Metadata Preflight:**
```bash
./scripts/ci_manager.sh preflight cli-proxy-api-bin
```

**4. Run Publish Path Verification (Container/CI Recommended):**
```bash
./scripts/ci_manager.sh run-publish claude-code-stable-bin --dry-run --verify-install
```

**5. Run Package Validation:**
```bash
./scripts/ci_manager.sh run-test antigravity-tools-bin
```

This path uses an ephemeral Arch container locally, builds the package, installs it with `pacman -U`, and runs smoke checks against the installed files.

## ➕ Adding a New Package

Please refer to [CONTRIBUTING.md](docs/CONTRIBUTING.md) for the standard process of adding and maintaining packages.

Each package directory now lives under `packages/<pkgname>/` and keeps only:
- `package.conf` as the PackageSpec v1 source of truth
- optional `hooks.sh` for special upstream logic
- optional `files/` for static assets such as service units or licenses

`PKGBUILD` and `.SRCINFO` are generated only in temporary workspaces during local runs and CI.

## 🔑 Integration & Secrets

For detailed setup instructions, including required publishing secrets (`AUR_SSH_PRIVATE_KEY`, `AUR_USERNAME`, and `AUR_EMAIL`) and global configuration, please refer to [INTEGRATION.md](docs/INTEGRATION.md).

---
*Maintained by [orange-guo](https://github.com/orange-guo)*
