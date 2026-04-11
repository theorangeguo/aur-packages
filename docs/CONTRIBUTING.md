# Contributing & Packaging Guide

This repository is template-driven. Each package directory declares a package via `package.conf`, with optional `hooks.sh` and `files/` overrides. `PKGBUILD` and `.SRCINFO` are generated only during local runs and CI.

## 📋 Standard Process for New Packages

### 1. Create Package Directory
Create a new directory whose name matches `PKGNAME`.

```bash
mkdir my-package-name
```

### 2. Create `package.conf`
This is the package source of truth.

Typical fields include:

```bash
PKGNAME=my-package-name
PACKAGE_TEMPLATE=binary-archive
UPSTREAM_TYPE=github-release-assets

PKGDESC="My package description"
URL="https://github.com/upstream/project"
LICENSES=('MIT')
ARCHES=('x86_64')
DEPENDS=()
MAKEDEPENDS=()
OPTIONS=('!strip')
PROVIDES=('my-package-name')
CONFLICTS=('my-package-name')

UPSTREAM_REPO_USER="upstream-user"
UPSTREAM_REPO_NAME="project"
UPSTREAM_TAG_PREFIX="v"

ASSET_SELECTOR_X86_64='^project_.*_linux_amd64\.tar\.gz$'
SOURCE_RENAME_X86_64='${pkgname}-${pkgver}-x86_64.tar.gz'

BINARY_NAME=my-binary
INSTALL_BIN_PATH=/usr/bin/my-binary

LOCAL_FILES=()
DOC_FILES=()
LICENSE_FILES=('LICENSE')
TEST_PATHS=()
TEST_EXECUTABLES=()

INSTALL_MODE=generated
SERVICE_MODE=none
```

### 3. Add Overrides Only If Needed

#### `hooks.sh`
Add this only when the built-in upstream resolvers are not enough.

Current rule: special upstream logic should live in `resolve_upstream_state()`.

```bash
#!/bin/bash

resolve_upstream_state() {
    RESOLVED_VERSION="1.2.3"
    RESOLVED_SOURCE_URL_X86_64="https://example.com/my-package-1.2.3.tar.gz"
}
```

You may also set additional `STATE_*` variables for template rendering. If a state value must be preserved in the rendered `PKGBUILD`, declare it in `PERSIST_STATE_KEYS`, for example `PERSIST_STATE_KEYS=('BINARY_TAG')`.

#### `files/`
Use this for static assets such as:
- `LICENSE`
- systemd service units
- static `.install` scripts
- other local packaging files

### 4. Pick the Right Template

Current built-in packaging templates:
- `binary-archive` — zip/tar.gz style binary packages
- `deb-repack` — `.deb` repackaging
- `appimage-desktop` — AppImage extraction plus desktop/icon setup

Current built-in upstream resolvers:
- `github-release-assets`
- `custom-hook`

Template-driven install tests automatically validate common installed outputs such as:
- `INSTALL_BIN_PATH`
- generated or static service files
- appimage desktop entries
- license files under `/usr/share/licenses/${PKGNAME}/`

Use `TEST_PATHS` and `TEST_EXECUTABLES` only when a package needs extra smoke-check assertions beyond the template defaults.

Both fields must contain absolute installed paths. `TEST_EXECUTABLES` checks that the installed path exists and has the executable bit set; it does not run the command.

### 5. Local Verification
Before committing, test the package locally from the repository root.

```bash
./scripts/ci_manager.sh run_update my-package-name --dry-run
./scripts/ci_manager.sh run_test my-package-name
```

This is the smallest meaningful test in this repo. It resolves upstream state, renders a temporary `PKGBUILD`, refreshes checksums, generates `.SRCINFO`, and verifies the build.

`run_test` is the stronger validation path. It runs in an Arch container, builds the package, installs it with `pacman -U`, and checks the installed files.

Use `--force` when you need to re-run packaging logic even if the version matches AUR.

### 6. Update Documentation
When adding or removing packages, update `README.md`.

### 7. Commit & Push
Commit the package directory and docs changes.

## 🔄 Maintenance

### How updates work
The scheduled workflow does this for each package:
1. Discover package directories by `package.conf`
2. Read current package state from the AUR repo
3. Resolve upstream version and asset URLs
4. Render a temporary `PKGBUILD`
5. Refresh checksums and generate `.SRCINFO`
6. Build locally in CI
7. Push the rendered package contents to AUR

### Packaging-only changes
If upstream version stays the same but rendered package contents change, the automation bumps `pkgrel` based on the current AUR repo state.

## 🧩 Special Upstreams

If a package cannot use `github-release-assets`, implement `hooks.sh` with `resolve_upstream_state()`.

Rules:
- It must set `RESOLVED_VERSION`
- It may set `RESOLVED_SOURCE_URL_X86_64`, `RESOLVED_SOURCE_URL_AARCH64`, and `STATE_*`
- It should not edit generated `PKGBUILD` files directly; prefer `STATE_*` plus `PERSIST_STATE_KEYS` instead
- It should fail with a non-zero status on error

## 📏 Technical Standards

### Package directory layout

```text
package-name/
  package.conf
  hooks.sh        # optional
  files/          # optional
```

### Generated files
- Do **NOT** commit `.SRCINFO`
- Do **NOT** commit generated `PKGBUILD`
- Treat `package.conf` as the canonical package definition

### Service files and install scripts
- Prefer `INSTALL_MODE=generated` for ordinary user-service packages
- Use static files under `files/` when the install messaging is unusual or package-specific
- If a service is installed, the install guidance must clearly distinguish User Level vs System Level service management

### Security & scripting
- Validate package paths and names
- Keep special logic in `hooks.sh`, not in generated files
- Build as non-root `builder`
- Prefer simple, top-level declarations in `package.conf`
