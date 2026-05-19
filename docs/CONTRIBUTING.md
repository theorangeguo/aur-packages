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
- Include the architecture in architecture-specific source rename values, for example `rename = '''${pkgname}-${pkgver}-x86_64.tar.gz'''` under `[inputs.sources.<name>]`.

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

[version]
from = "origin"
origin = "release"

[origins.release]
type = "github-release"
repo = "upstream-user/project"
tag_prefix = "v"

[inputs.sources.binary]
from = "github-release-asset"
origin = "release"
arch = "x86_64"
selector = '''^project_.*_linux_amd64\.tar\.gz$'''
rename = '''${pkgname}-${pkgver}-x86_64.tar.gz'''

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

### 3. Add Artifact Preparation When Needed

For packages whose consumed archives are produced by this repository first, keep the AUR side as `template = "binary-archive"` and declare package artifacts instead of adding a package-specific workflow:

```toml
[version]
from = "artifact"
artifact = "my-binary-archive"

[origins.upstream]
type = "github-release"
repo = "upstream-user/upstream-project"
tag_prefix = "v"

[package]
binary_name = "my-binary"
binary_source_path = "my-binary"
install_bin_path = "/usr/bin/my-binary"

[inputs.sources.my-binary-archive]
from = "artifact"
artifact = "my-binary-archive"
arch = "x86_64"
rename = '''${pkgname}-${pkgver}-x86_64.tar.gz'''

[inputs.artifacts.my-binary-archive]
type = "archive"
rev = 1
version_template = '''${origin_version}.r${artifact_rev}'''
arches = ["x86_64"]

[inputs.artifacts.my-binary-archive.recipe]
type = "cargo-build"
origin = "upstream"
source_dir = '''upstream-project-${origin_version}'''
patches = ["files/0001-example.patch"]
makedepends = ["ca-certificates", "curl", "git", "patch", "rust", "tar"]
cargo_build_args = ["--release", "--frozen"]
run_check = false
archive_files = [
  "target/release/my-binary:my-binary:755",
  "LICENSE:LICENSE:644",
]

[inputs.artifacts.my-binary-archive.storage]
type = "github-release"
repo = "orange-guo/aur-packages"
tag_prefix = "my-package-name-v"

[inputs.artifacts.my-binary-archive.outputs.x86_64]
asset_name = '''${pkgname}-${pkgver}-x86_64-unknown-linux-gnu.tar.gz'''
```

`rev` is part of the artifact version. Bump it when the patchset or build recipe changes without an upstream version change. `run-publish` can publish missing artifacts, while `run-test` defaults to `readonly` artifact mode so validation does not mutate GitHub Releases. Use `run-test --artifact-mode local` when you need to validate the artifact recipe itself without publishing it.

Publishing artifacts requires GitHub CLI authentication (`gh`) with permission to create or update releases in the configured storage repo.

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

Current built-in origin/source resolvers:

- `[origins.*] type = "github-release"`
- `[version] from = "hook"` with `[inputs.sources.*] from = "hook"`
- `[inputs.sources.*] from = "github-release-asset"`

GitHub release sources can consume either the latest release or a release family. Set `[origins.<name>] release_tag_prefix` plus `[inputs.sources.<name>] asset_name` to select the newest release whose tag starts with the prefix and contains the exact expected asset names.

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
python3 scripts/aurpkg.py prepare-artifacts my-package-name --artifact-mode readonly
python3 scripts/aurpkg.py run-publish my-package-name --dry-run
python3 scripts/aurpkg.py run-test my-package-name
```

For shared script or workflow changes, run `run-publish --dry-run` and `run-test` for every package in the affected matrix. If external infrastructure prevents completion, record the exact failing command and dependency instead of treating the change as verified.

The scheduled publish workflow uses `detect-updates` first. Detection resolves upstream metadata and writes a cached fingerprint under `.update-state/`; it does not clone AUR, build, or publish. Manual runs with a package use `dispatch_policy=auto`, which selects that package even when the detector state is unchanged. Use `dispatch_policy=selected` only with a single package.

The CLI accepts either a bare package name like `my-package-name` or an explicit path like `packages/my-package-name`.

Run `prepare-artifacts --artifact-mode publish` for self-built `-bin` packages when the expected GitHub Release artifact does not exist yet and you want to publish it manually before `run-publish`/`run-test`.

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

If a package cannot use `github-release` origins plus `github-release-asset` sources, implement `hooks.sh` with `resolve_upstream_state()`.

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
