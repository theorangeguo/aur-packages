# GitHub Actions Integration Guide

This repository uses a template-driven CI pipeline to automate AUR package maintenance and package validation.

Two workflows matter:
- `.github/workflows/aur-publish.yml` for scheduled/manual publish to AUR
- `.github/workflows/package-test.yml` for build+install verification on pull requests, pushes, and manual runs

## 1. Prerequisites

### GitHub Repository Settings
For publishing, configure these repository secrets or variables:

| Name | Description | Required |
|------|-------------|----------|
| `AUR_SSH_PRIVATE_KEY` | SSH private key for AUR authentication. | **Yes** |
| `AUR_USERNAME` | Your AUR username. | **Yes** |
| `AUR_EMAIL` | Email address used for AUR commits. | **Yes** |

The private key must be unencrypted.

`package-test.yml` does not require AUR publishing secrets.

## 2. Package Configuration

The pipeline auto-discovers packages by locating `package.conf` files.

Each package directory should contain:

```text
package-name/
  package.conf
  hooks.sh        # optional
  files/          # optional
```

`package.conf` is the source of truth. CI renders `PKGBUILD` and `.SRCINFO` only during execution.

## 3. How It Works

The workflows in `.github/workflows/aur-publish.yml` and `.github/workflows/package-test.yml` delegate all logic to `scripts/`.

The validation workflow reuses the same discovery matrix, but runs `./scripts/ci_manager.sh run_test <package_dir>` instead of publishing.

### Phase 1: Discovery
- **Command**: `scripts/ci_manager.sh discover`
- **Action**: scans for directories containing `package.conf`
- **Output**: GitHub Actions matrix JSON

### Phase 2: Validation execution
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

For `aur-publish.yml`, the build path continues from there by syncing and pushing the rendered package contents to AUR.

## 4. Local Testing

Use the same manager script locally:

```bash
sudo ./scripts/ci_manager.sh install
sudo ./scripts/ci_manager.sh setup_user
./scripts/ci_manager.sh run_update antigravity-tools-bin --dry-run
./scripts/ci_manager.sh run_test antigravity-tools-bin
```

This is the repo's standard test path.

`run_test` uses an ephemeral Arch container locally and the job container in GitHub Actions. It builds the package, installs it, and verifies expected files.

When the manager is invoked as root, it switches to the `builder` user before running package builds. Non-root local runs use the current user.

## 5. Security Measures

The scripts enforce:
- input sanitization for package paths
- non-root builds via the `builder` user
- temporary SSH key handling during push
- package rendering from trusted local configs only
