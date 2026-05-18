# Contributing & Packaging Guide

This repository is template-driven. Each package directory declares a PackageSpec v1 via `package.conf`, with optional `hooks.sh` and `files/` overrides. `PKGBUILD` and `.SRCINFO` are generated only during local runs and CI.

For the end-to-end repository workflow, see [WORKFLOW.md](WORKFLOW.md). For framework boundaries, extension points, and anti-corruption rules, see [PACKAGE_FRAMEWORK.md](PACKAGE_FRAMEWORK.md).

## 📋 Standard Process for New Packages

### 1. Create Package Directory
Create a new directory under `packages/` whose name matches `PKGNAME`.

```bash
mkdir -p packages/my-package-name
```

### 2. Create `package.conf`
This is the PackageSpec v1 source of truth.

Naming conventions:

- Keep the package directory name identical to `PKGNAME`.
- Prefer kebab-case package names. Versioned library packages may include a dot when that matches Arch naming conventions, such as `wlroots0.20-vmwgfx`.
- Let `-bin` in `PKGNAME` communicate binary packaging; keep `PKGDESC` focused on the software itself rather than adding redundant `(Binary)` wording.
- Include the architecture in architecture-specific source rename fields, for example `SOURCE_RENAME_X86_64='${pkgname}-${pkgver}-x86_64.tar.gz'`.

Typical fields include:

```bash
PACKAGE_SPEC_VERSION=1

PKGNAME=my-package-name
PACKAGE_TEMPLATE=binary-archive
UPSTREAM_TYPE=github-release-assets

PKGDESC="My package description"
URL="https://github.com/upstream/project"
LICENSES=('MIT')
ARCHES=('x86_64')
DEPENDS=()
MAKEDEPENDS=()
CHECKDEPENDS=()
OPTDEPENDS=()
OPTIONS=('!strip')
PROVIDES=('my-package-name')
CONFLICTS=('my-package-name')
VALIDPGPKEYS=()

UPSTREAM_REPO_USER="upstream-user"
UPSTREAM_REPO_NAME="project"
UPSTREAM_TAG_PREFIX="v"

ASSET_SELECTOR_X86_64='^project_.*_linux_amd64\.tar\.gz$'
SOURCE_RENAME_X86_64='${pkgname}-${pkgver}-x86_64.tar.gz'

BINARY_NAME=my-binary
INSTALL_BIN_PATH=/usr/bin/my-binary
BINARY_SOURCE_PATH=my-binary
WRAPPER_SOURCE_PATH=my-wrapper
WRAPPER_INSTALL_PATH=/usr/bin/my-wrapper

LOCAL_FILES=('files/my-wrapper')
DOC_FILES=()
LICENSE_FILES=('LICENSE')
TEST_PATHS=()
TEST_EXECUTABLES=()
TEST_COMMANDS=('/usr/bin/my-binary --version')

INSTALL_MODE=generated
SERVICE_MODE=none
```

Useful optional fields:

- `PACKAGING_REPO_URL` — overrides the dedicated `# Packaging Repo:` comment added to rendered `PKGBUILD`s. This is separate from the AUR `url` metadata field, which should still point at upstream.
- `BINARY_SOURCE_PATH` — path inside the extracted source archive to install as the main binary. Glob patterns are supported for archives with versioned top-level directories. Use single-quoted template placeholders such as `'${pkgname}-${pkgver}-x86_64'`; do not cross-reference other PackageSpec variables.
- `WRAPPER_SOURCE_PATH`, `WRAPPER_INSTALL_PATH`, `WRAPPER_MODE` — install an additional wrapper script alongside the main binary.
- `TEST_COMMANDS` — commands executed after install during smoke checks.

For packages whose binary assets are built by this repository first, keep the AUR side as `PACKAGE_TEMPLATE=binary-archive` and add a declarative binary-release block instead of a package-specific workflow:

```bash
BINARY_RELEASE_ENABLED=true
BINARY_RELEASE_TEMPLATE=source-cargo
BINARY_RELEASE_REV=1
BINARY_RELEASE_VERSION_TEMPLATE='${upstream_version}.r${release_rev}'
BINARY_RELEASE_TAG_PREFIX=my-package-name-v
BINARY_RELEASE_REPO=orange-guo/aur-packages
BINARY_RELEASE_ARCHES=('x86_64')
BINARY_RELEASE_ASSET_X86_64='${pkgname}-${pkgver}-x86_64-unknown-linux-gnu.tar.gz'

BINARY_RELEASE_UPSTREAM_TYPE=github-source-archive
BINARY_RELEASE_UPSTREAM_REPO_USER=upstream-user
BINARY_RELEASE_UPSTREAM_REPO_NAME=upstream-project
BINARY_RELEASE_UPSTREAM_TAG_PREFIX=v
BINARY_RELEASE_SOURCE_DIR='upstream-project-${upstream_version}'
BINARY_RELEASE_PATCH_FILES=('files/0001-example.patch')
BINARY_RELEASE_MAKEDEPENDS=('ca-certificates' 'curl' 'git' 'patch' 'rust' 'tar')
BINARY_RELEASE_CARGO_BUILD_ARGS=('--release' '--frozen')
BINARY_RELEASE_RUN_CHECK=false
BINARY_RELEASE_ARCHIVE_FILES=(
    'target/release/my-binary:my-binary:755'
    'LICENSE:LICENSE:644'
)

UPSTREAM_REPO_USER=orange-guo
UPSTREAM_REPO_NAME=aur-packages
UPSTREAM_RELEASE_TAG_PREFIX=my-package-name-v
UPSTREAM_TAG_PREFIX=my-package-name-v
UPSTREAM_ASSET_NAME_X86_64='${pkgname}-${pkgver}-x86_64-unknown-linux-gnu.tar.gz'
```

`BINARY_RELEASE_REV` is part of `pkgver`. Bump it when the patchset or build recipe changes without an upstream version change. The generic `.github/workflows/build-binary-releases.yml` workflow discovers packages with `BINARY_RELEASE_ENABLED=true`, builds the configured assets, publishes them to GitHub Releases, and then the normal AUR package pipeline consumes those release assets.

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
- `source-meson` — source builds using Meson/Ninja with optional patches

Typical extra fields for `source-meson`:

```bash
SOURCE_RENAME='${pkgname}'
SOURCE_DIR='${pkgname}'
BUILD_DIR=build
PATCH_FILES=('files/0001-example.patch')
MESON_OPTIONS=('-Dexamples=false')
RUN_CHECK=false
CHECK_ARGS=()
```

Other template-specific fields:

- `deb-repack`: `DEB_RELOCATE_USR_LOCAL=true`
- `appimage-desktop`: `APPIMAGE_APPDIR_NAME`, `DESKTOP_EXEC_REWRITE`, `DESKTOP_NAME_REWRITE`, `DESKTOP_CANDIDATES`, `ICON_CANDIDATES`
- `binary-archive`: `WRAPPER_*`, `BINARY_SOURCE_PATH`; `BINARY_SOURCE_PATH`, `DOC_FILES`, and `LICENSE_FILES` may use glob patterns inside the extracted source archive.

Current built-in upstream resolvers:
- `github-release-assets`
- `custom-hook`

`github-release-assets` can consume either the latest release or a release family. Set `UPSTREAM_RELEASE_TAG_PREFIX` plus `UPSTREAM_ASSET_NAME_<ARCH>` to select the newest release whose tag starts with the prefix and contains the exact expected asset names.

Template-driven package validation automatically checks common installed outputs such as:
- `INSTALL_BIN_PATH`
- generated or static service files
- appimage desktop entries
- license files under `/usr/share/licenses/${PKGNAME}/`

Use `TEST_PATHS`, `TEST_EXECUTABLES`, and `TEST_COMMANDS` only when a package needs extra smoke-check assertions beyond the template defaults.

`TEST_PATHS` and `TEST_EXECUTABLES` must contain absolute installed paths. `TEST_EXECUTABLES` checks that the installed path exists, is executable, and is owned by the package. `TEST_COMMANDS` executes the provided commands after install.

### 5. Local Verification
Before committing, test the package locally from the repository root.

Every package-affecting change must pass both package validation and publish-path dry-run before it is reported as complete:

```bash
./scripts/ci_manager.sh build-binary-release my-package-name --dry-run
./scripts/ci_manager.sh build-binary-release my-package-name --skip-publish
./scripts/ci_manager.sh run-publish my-package-name --dry-run
./scripts/ci_manager.sh run-test my-package-name
```

For shared script or workflow changes, run `run-publish --dry-run` and `run-test` for every package in the affected matrix. If external infrastructure prevents completion, record the exact failing command and dependency instead of treating the change as verified.

The scheduled publish workflow uses `detect-updates` first. Detection resolves upstream metadata and writes a cached fingerprint under `.update-state/`; it does not clone AUR, build, or publish. Manual runs with a package use `dispatch_policy=auto`, which selects that package even when the detector state is unchanged. Use `dispatch_policy=selected` only with a single package.

The manager accepts either a bare package name like `my-package-name` or an explicit path like `packages/my-package-name`.

Run `build-binary-release` before `run-publish`/`run-test` for self-built `-bin` packages when the expected GitHub release asset does not exist yet.

This is the smallest meaningful test in this repo. It resolves upstream state, renders a temporary `PKGBUILD`, refreshes checksums, generates `.SRCINFO`, and verifies the build.

`run-test` is the stronger validation path. It runs in an Arch container, builds the package, installs it with `pacman -U`, and checks the installed files. The scheduled AUR publish workflow now uses that same package validation path before publishing package updates.

If you manually use `run-publish --verify-install`, prefer doing so inside CI or an ephemeral container rather than on a long-lived host system.

### 6. Update Documentation
When adding or removing packages, update `README.md`.

### 7. Commit & Push
Commit the package directory and docs changes.

## 🔄 Maintenance

### How updates work
The scheduled workflow does this for each package:
1. Discover package directories by PackageSpec v1 `package.conf`
2. Read current package state from the AUR repo
3. Resolve upstream version and asset URLs
4. Render a temporary `PKGBUILD`
5. Refresh checksums and generate `.SRCINFO`
6. Build locally in CI
7. Install the built package and run smoke checks
8. Publish to AUR only if package validation passes

### Packaging-only changes
If upstream version stays the same but rendered package contents change, the automation bumps `pkgrel` based on the current AUR repo state.

## 🧩 Special Upstreams

If a package cannot use `github-release-assets`, implement `hooks.sh` with `resolve_upstream_state()`.

Rules:
- It must set `RESOLVED_VERSION`
- It may set `RESOLVED_SOURCE_URL`, `RESOLVED_SOURCE_URL_X86_64`, `RESOLVED_SOURCE_URL_AARCH64`, and `STATE_*`
- It should not edit generated `PKGBUILD` files directly; prefer `STATE_*` plus `PERSIST_STATE_KEYS` instead
- It should fail with a non-zero status on error

## 📏 Technical Standards

### Package directory layout

```text
packages/
  package-name/
    package.conf
    hooks.sh        # optional
    files/          # optional
```

### Generated files
- Do **NOT** commit `.SRCINFO`
- Do **NOT** commit generated `PKGBUILD`
- Treat `package.conf` as the canonical PackageSpec v1 definition

### Service files and install scripts
- Prefer `INSTALL_MODE=generated` for ordinary user-service packages
- Use static files under `files/` when the install messaging is unusual or package-specific
- If a service is installed, the install guidance must clearly distinguish User Level vs System Level service management

### Security & scripting
- Validate package paths and names
- Keep special logic in `hooks.sh`, not in generated files
- Build as non-root `builder`
- Prefer simple, top-level declarations in `package.conf`
