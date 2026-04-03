# GitHub Actions Integration Guide

This repository uses a template-driven CI pipeline to automate AUR package maintenance.

## 1. Prerequisites

### GitHub Repository Settings
Configure these repository secrets or variables:

| Name | Description | Required |
|------|-------------|----------|
| `AUR_SSH_PRIVATE_KEY` | SSH private key for AUR authentication. | **Yes** |
| `AUR_USERNAME` | Your AUR username. | **Yes** |
| `AUR_EMAIL` | Email address used for AUR commits. | **Yes** |

The private key must be unencrypted.

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

The workflow in `.github/workflows/aur-publish.yml` delegates all logic to `scripts/`.

### Phase 1: Discovery
- **Command**: `scripts/ci_manager.sh discover`
- **Action**: scans for directories containing `package.conf`
- **Output**: GitHub Actions matrix JSON

### Phase 2: Execution
For each package:

1. Install dependencies in the Arch container
2. Create the non-root `builder` user
3. Read the current `pkgver/pkgrel` from the AUR repo
4. Resolve upstream version and asset URLs
5. Render a temporary `PKGBUILD` and optional generated assets
6. Run `updpkgsums`
7. Generate `.SRCINFO`
8. Build with `makepkg`
9. Push the rendered package repo contents to AUR

## 4. Local Testing

Use the same manager script locally:

```bash
sudo ./scripts/ci_manager.sh install
sudo ./scripts/ci_manager.sh setup_user
./scripts/ci_manager.sh run_update antigravity-tools-bin --dry-run
```

This is the repo's standard test path.

## 5. Security Measures

The scripts enforce:
- input sanitization for package paths
- non-root builds via the `builder` user
- temporary SSH key handling during push
- package rendering from trusted local configs only
