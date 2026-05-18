# GitHub Actions Integration Guide

This repository uses a template-driven CI pipeline to automate AUR package maintenance and package validation.

For the higher-level workflow architecture, see [WORKFLOW.md](WORKFLOW.md).

Core workflows:
- `.github/workflows/aur-publish.yml` for scheduled/manual publish to AUR
- `.github/workflows/package-test.yml` for package validation on pull requests, pushes, and manual runs
- `.github/workflows/build-binary-releases.yml` for scheduled/manual/branch-push production of repo-built binary-release assets

All manually dispatched workflows accept an optional single-package input so you can rerun one package without fanning out across the whole repository.

## 1. Prerequisites

### GitHub Repository Settings
For publishing, configure these repository secrets or variables:

| Name | Description | Required |
|------|-------------|----------|
| `AUR_SSH_PRIVATE_KEY` | SSH private key for AUR authentication. | **Yes** |
| `AUR_USERNAME` | Your AUR username. | **Yes** |
| `AUR_EMAIL` | Email address used for AUR commits. | **Yes** |

The private key must be unencrypted.

`package-test.yml` and `build-binary-releases.yml` do not require AUR publishing secrets.

## 2. Package Configuration

The pipeline auto-discovers packages by locating PackageSpec v1 `package.toml` files.

Each package directory should contain:

```text
packages/
  package-name/
    package.toml
    hooks.sh        # optional
    files/          # optional
```

`package.toml` is the PackageSpec v1 source of truth. CI renders `PKGBUILD` and `.SRCINFO` only during execution.

## 3. How It Works

The workflows in `.github/workflows/aur-publish.yml`, `.github/workflows/package-test.yml`, and `.github/workflows/build-binary-releases.yml` delegate all logic to `scripts/`.

The validation workflow reuses the same discovery matrix, but runs `./scripts/ci_manager.sh run-test <pkgname-or-path>` instead of publishing. The publish workflow uses the same package validation path before it stages and pushes updates to AUR.

### Phase 1: Discovery
- **Command**: `scripts/ci_manager.sh discover`
- **Action**: scans for directories containing PackageSpec v1 `package.toml`
- **Output**: GitHub Actions matrix JSON

On pull requests and ordinary pushes, discovery narrows the validation matrix to the packages touched by the diff. If automation files under `scripts/` or `.github/workflows/` change, discovery falls back to a full-package sweep.

### Phase 2: Package validation execution
For each package in `package-test.yml`:

1. Install dependencies in the Arch container
2. Create the non-root `builder` user
3. Resolve upstream version and asset URLs
4. Render a temporary `PKGBUILD` and optional generated assets
5. Run `updpkgsums`
6. Generate `.SRCINFO`
7. Build with `makepkg`
8. Install the built package with `pacman -U`
9. Run smoke checks against the installed files

For `aur-publish.yml`, the same build and smoke-check path runs first, then the workflow syncs and pushes the rendered package contents to AUR only if package validation passes.

## 4. Local Testing

Use the same manager script locally:

```bash
sudo ./scripts/ci_manager.sh install
sudo ./scripts/ci_manager.sh setup-user
./scripts/ci_manager.sh run-publish antigravity-tools-bin --dry-run
./scripts/ci_manager.sh run-test antigravity-tools-bin
```

The manager accepts either a bare package name or an explicit `packages/<pkgname>` path.

This is the repo's standard test path.

`run-test` uses an ephemeral Arch container locally and the job container in GitHub Actions. It builds the package, installs it, and verifies expected files.

Local `run-test` requires Docker or Podman.

Use `run-publish --verify-install` in CI or an ephemeral container, not on a long-lived host system, because it installs the candidate package before publishing.

When the manager is invoked as root, package builds still run as the non-root `builder` user, but the root-owned publish path can install the built package for smoke testing before pushing to AUR. Non-root local runs use the current user.

## 5. Security Measures

The scripts enforce:
- input sanitization for package paths
- non-root builds via the `builder` user
- temporary SSH key handling during push with AUR host fingerprint verification
- package rendering from trusted local configs only
