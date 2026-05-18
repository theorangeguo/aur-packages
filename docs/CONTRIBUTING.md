# Contributing & Packaging Guide

This repository is template-driven. Each package directory declares a PackageSpec v1 in `package.toml`, with optional `hooks.sh` and `files/` assets. `PKGBUILD` and `.SRCINFO` are generated only during local runs and CI.

For the end-to-end repository workflow, see [WORKFLOW.md](WORKFLOW.md). For framework boundaries, extension points, and anti-corruption rules, see [PACKAGE_FRAMEWORK.md](PACKAGE_FRAMEWORK.md).

## 📋 Standard Process for New Packages

### 1. Create Package Directory

Create a new directory under `packages/` whose name matches the PackageSpec `name`.

```bash
mkdir -p packages/my-package-name
```

### 2. Create `package.toml`

This is the PackageSpec v1 source of truth. It is strict TOML: no shell execution, no imports, no inheritance, and no package-specific workflow logic.

Naming conventions:

- Keep the package directory name identical to `name`.
- Prefer kebab-case package names. Versioned library packages may include a dot when that matches Arch naming conventions, such as `wlroots0.20-vmwgfx`.
- Let `-bin` in the package name communicate binary packaging; keep `desc` focused on the software itself rather than adding redundant `(Binary)` wording.
- Include the architecture in architecture-specific source rename values, for example `source_rename = '''${pkgname}-${pkgver}-x86_64.tar.gz'''` under `[upstream.assets.x86_64]`.

Typical binary package spec:

```toml
spec_version = 1
name = "my-package-name"
template = "binary-archive"

[metadata]
desc = "My package description"
url = "https://github.com/upstream/project"
licenses = ["MIT"]
arches = ["x86_64"]
depends = []
makedepends = []
checkdepends = []
optdepends = []
options = ["!strip"]
provides = ["my-package-name"]
conflicts = ["my-package-name"]
validpgpkeys = []

[upstream]
type = "github-release-assets"
repo = "upstream-user/project"
tag_prefix = "v"

[upstream.assets.x86_64]
selector = '''^project_.*_linux_amd64\.tar\.gz$'''
source_rename = '''${pkgname}-${pkgver}-x86_64.tar.gz'''

[package]
binary_name = "my-binary"
binary_source_path = "my-binary"
install_bin_path = "/usr/bin/my-binary"
wrapper_source_path = "my-wrapper"
wrapper_install_path = "/usr/bin/my-wrapper"

[files]
local = ["files/my-wrapper"]
docs = []
licenses = ["LICENSE"]

[install]
mode = "generated"

[service]
mode = "none"

[tests]
commands = ["/usr/bin/my-binary --version"]
```

Useful optional fields:

- `packaging_repo_url` — overrides the dedicated `# Packaging Repo:` comment added to rendered `PKGBUILD`s. This is separate from the AUR `url` metadata field, which should still point at upstream.
- `[package] binary_source_path` — path inside the extracted source archive to install as the main binary. Glob patterns are supported for archives with versioned top-level directories. Use literal TOML strings for template placeholders such as `'''${pkgname}-${pkgver}-x86_64'''`; do not cross-reference other PackageSpec values.
- `[package] wrapper_source_path`, `wrapper_install_path`, `wrapper_mode` — install an additional wrapper script alongside the main binary.
- `[tests] commands` — commands executed after install during smoke checks.
- `[state] persist` — state keys from `STATE_*` hook outputs that should be rendered into generated packaging files.

### 3. Add Binary-Release Producer Configuration When Needed

For packages whose binary assets are built by this repository first, keep the AUR side as `template = "binary-archive"` and add a declarative `[binary_release]` component instead of a package-specific workflow:

```toml
[binary_release]
enabled = true
template = "source-cargo"
rev = 1
version_template = '''${upstream_version}.r${release_rev}'''
tag_prefix = "my-package-name-v"
repo = "orange-guo/aur-packages"
arches = ["x86_64"]
source_dir = '''upstream-project-${upstream_version}'''
patch_files = ["files/0001-example.patch"]
makedepends = ["ca-certificates", "curl", "git", "patch", "rust", "tar"]
cargo_build_args = ["--release", "--frozen"]
run_check = false
archive_files = [
  "target/release/my-binary:my-binary:755",
  "LICENSE:LICENSE:644",
]

[binary_release.upstream]
type = "github-source-archive"
repo = "upstream-user/upstream-project"
tag_prefix = "v"

[binary_release.assets.x86_64]
name = '''${pkgname}-${pkgver}-x86_64-unknown-linux-gnu.tar.gz'''

[upstream]
type = "github-release-assets"
repo = "orange-guo/aur-packages"
release_tag_prefix = "my-package-name-v"
tag_prefix = "my-package-name-v"

[upstream.assets.x86_64]
asset_name = '''${pkgname}-${pkgver}-x86_64-unknown-linux-gnu.tar.gz'''
```

`rev` is part of `pkgver`. Bump it when the patchset or build recipe changes without an upstream version change. The generic `.github/workflows/build-binary-releases.yml` workflow discovers packages with `[binary_release] enabled = true`, builds the configured assets, publishes them to GitHub Releases, and then the normal AUR package pipeline consumes those release assets.

### 4. Add Overrides Only If Needed

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

You may also set additional `STATE_*` variables for template rendering. If a state value must be preserved in the rendered `PKGBUILD`, declare the suffix in TOML, for example:

```toml
[state]
persist = ["BINARY_TAG"]
```

Hooks must not mutate PackageSpec fields such as `BINARY_SOURCE_PATH`, service settings, file lists, or template-specific options. If a hook needs to do that, add a generic framework field instead.

#### `files/`

Use this for static assets such as:

- licenses
- wrappers
- systemd service units
- static `.install` scripts
- package patches
- other local packaging files

Declare local files by semantic role in `package.toml`; do not blindly include everything under `files/`.

### 5. Pick the Right Components

Current built-in packaging templates:

- `binary-archive` — zip/tar.gz style binary packages
- `deb-repack` — `.deb` repackaging
- `appimage-desktop` — AppImage extraction plus desktop/icon setup
- `source-meson` — source builds using Meson/Ninja with optional patches

Typical extra fields for `source-meson`:

```toml
[build]
source_rename = '''${pkgname}'''
source_dir = '''${pkgname}'''
build_dir = "build"
meson_options = ["-Dexamples=false"]
run_check = false
check_args = []

[files]
patches = ["files/0001-example.patch"]
```

Other template-specific fields:

- `deb-repack`: `[build] deb_relocate_usr_local = true`
- `appimage-desktop`: `[build] appimage_appdir_name`, `desktop_exec_rewrite`, `desktop_name_rewrite`, `desktop_candidates`, `icon_candidates`
- `binary-archive`: `[package] wrapper_*`, `binary_source_path`; `[files] docs` and `[files] licenses` may use glob patterns inside the extracted source archive.

Current built-in upstream resolvers:

- `github-release-assets`
- `custom-hook`

`github-release-assets` can consume either the latest release or a release family. Set `[upstream] release_tag_prefix` plus `[upstream.assets.<arch>] asset_name` to select the newest release whose tag starts with the prefix and contains the exact expected asset names.

Template-driven package validation automatically checks common installed outputs such as:

- `[package] install_bin_path`
- generated or static service files
- AppImage desktop entries
- license files under `/usr/share/licenses/${PKGNAME}/`

Use `[tests] paths`, `[tests] executables`, and `[tests] commands` only when a package needs extra smoke-check assertions beyond the template defaults.

`[tests] paths` and `[tests] executables` must contain absolute installed paths. Executable checks verify that the installed path exists, is executable, and is owned by the package. Commands run after install.

### 6. Local Verification

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

`run-test` is the stronger validation path. It runs in an Arch container, builds the package, installs it with `pacman -U`, and checks the installed files. The scheduled AUR publish workflow uses that same package validation path before publishing package updates.

If you manually use `run-publish --verify-install`, prefer doing so inside CI or an ephemeral container rather than on a long-lived host system.

### 7. Update Documentation

When adding or removing packages, update `README.md`.

### 8. Commit & Push

Commit the package directory and docs changes.

## 🔄 Maintenance

### How updates work

The scheduled workflow does this for each package:

1. Discover package directories by PackageSpec v1 `package.toml`
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
- It should not edit generated `PKGBUILD` files directly; prefer `STATE_*` plus `[state] persist` instead
- It should fail with a non-zero status on error

## 📏 Technical Standards

### Package directory layout

```text
packages/
  package-name/
    package.toml
    hooks.sh        # optional
    files/          # optional
```

### Generated files

- Do **NOT** commit `.SRCINFO`
- Do **NOT** commit generated `PKGBUILD`
- Treat `package.toml` as the canonical PackageSpec v1 definition

### Service files and install scripts

- Prefer `[install] mode = "generated"` for ordinary user-service packages
- Use static files under `files/` when the install messaging is unusual or package-specific
- If a service is installed, the install guidance must clearly distinguish User Level vs System Level service management

### Security & scripting

- Validate package paths and names
- Keep special logic in `hooks.sh`, not in generated files
- Build as non-root `builder`
- Prefer declarative component fields in `package.toml` over new package-specific shell branches
