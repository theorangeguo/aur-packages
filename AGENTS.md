# AGENTS.md

## Purpose
- This repo is an Arch Linux AUR package monorepo.
- Source-of-truth package definitions live in `package.conf`, optional `hooks.sh`, and optional `files/` assets.
- `PKGBUILD` and `.SRCINFO` are generated only in temporary workspaces during local runs and CI.
- Prefer small, package-scoped changes over broad cleanup.
- Do not introduce new tooling or languages unless the user asks.

## Read first
- `README.md`
- `docs/CONTRIBUTING.md`
- `docs/INTEGRATION.md`
- `.github/workflows/aur-publish.yml`
- `.github/workflows/package-test.yml`
- `scripts/ci_manager.sh`
- `scripts/auto_update.sh`
- `scripts/test_package.sh`
- `scripts/lib/`

## Repository facts and local rules
- No Cursor rules were found in `.cursor/rules/` or `.cursorrules`.
- No Copilot instructions were found in `.github/copilot-instructions.md`.
- CI auto-discovers package directories by locating `package.conf` files.
- The current package state baseline comes from the AUR repo, not from this monorepo.
- Keep workflow YAML thin; most behavior belongs in `scripts/`.
- Build steps must run as the non-root `builder` user.

## Repository workflow
- Main flow: discover packages -> read AUR state -> resolve upstream -> render temporary `PKGBUILD` -> refresh checksums -> generate `.SRCINFO` -> build -> publish to AUR.
- Validation flow: discover packages -> resolve upstream -> render temporary `PKGBUILD` -> build -> install package in a container -> run smoke checks.
- Main entrypoints: `scripts/ci_manager.sh discover`, `scripts/ci_manager.sh run_update <package_dir> ...`, `scripts/ci_manager.sh run_test <package_dir>`, `scripts/auto_update.sh <package_dir> ...`, `scripts/test_package.sh <package_dir>`
- When touching update logic, inspect `scripts/auto_update.sh`, the relevant files under `scripts/lib/`, and any package-local `hooks.sh`.

## Build / lint / test / verification commands

### Environment setup
```bash
sudo ./scripts/ci_manager.sh install
sudo ./scripts/ci_manager.sh setup_user
```

### Preferred verification for one package
```bash
./scripts/ci_manager.sh run_update <package_dir> --dry-run
./scripts/ci_manager.sh run_test <package_dir>
```
- This is the repo's closest equivalent to a standard test command.
- It resolves upstream metadata, renders temporary packaging files, refreshes checksums, generates `.SRCINFO`, and verifies one package build.
- `run_test` is the stronger validation path: it builds the package, installs it, and performs smoke checks against the installed files.

### Lower-level updater
```bash
bash scripts/auto_update.sh <package_dir> [--dry-run] [--skip-build]
```
- Prefer the manager wrapper unless you specifically need the lower-level script.

### Lint / format status
- No dedicated linter or formatter config was found (`shellcheck`, `shfmt`, `prettier`, `eslint`, `ruff`, `bats`, `pytest`, etc.).
- Match the surrounding style; keep diffs conservative and package-scoped.

## “Single test” guidance
- There is no unit-test framework in this repo.
- The smallest meaningful verification unit is one package directory.
- When asked to run a single test, prefer `./scripts/ci_manager.sh run_test <package_dir>` for install verification, or `./scripts/ci_manager.sh run_update <package_dir> --dry-run` for publish-path verification.
- Use `--skip-build` only for metadata-only debugging when build verification is intentionally unnecessary.

## Code style guidelines

### General
- Keep edits narrowly scoped to the affected package or script.
- Preserve existing comments unless they are inaccurate or stale.
- Do not rename package directories casually; directory name should match `PKGNAME` in `package.conf`.
- Update `README.md` when adding or removing packages.

### Bash / shell style
- Use `#!/bin/bash`.
- Existing scripts use `set -e`; keep that unless there is a strong reason not to.
- Prefer small helper functions for logging, validation, rendering, and grouped output.
- Use lowercase for function names, uppercase for script-level flags/config like `FORCE_UPDATE`, `DRY_RUN`, `PKG_DIR`, and `local` for function-scoped variables.
- Quote variable expansions unless unquoted behavior is required.
- Prefer straightforward shell over clever one-liners.

### Imports / sourcing
- Only source known local files.
- In this repo, package-specific override logic may be sourced from `hooks.sh`.
- Do not source remote content or arbitrary user-provided paths.

### `package.conf` style
- Treat `package.conf` as the package source of truth.
- Keep key fields simple, top-level, and easy to source from Bash.
- Prefer explicit arrays like `ARCHES=('x86_64')`, `DEPENDS=()`, `LICENSES=('MIT')`.
- Template selection should be declarative: `PACKAGE_TEMPLATE=...`, `UPSTREAM_TYPE=...`.
- For GitHub-backed packages, use `UPSTREAM_REPO_USER`, `UPSTREAM_REPO_NAME`, `UPSTREAM_TAG_PREFIX`, and `ASSET_SELECTOR_*` fields.
- If install smoke checks need package-specific assertions, use `TEST_PATHS` and `TEST_EXECUTABLES`.
- Prefer package-local static files under `files/` over embedding large blobs in scripts.

### Template / hook boundaries
- Keep ordinary packages template-only.
- Use `hooks.sh` only for special upstream resolution or genuinely exceptional packaging behavior.
- `resolve_upstream_state()` should set `RESOLVED_VERSION` and optional `RESOLVED_SOURCE_URL_*` / `STATE_*` values.
- If hook state must persist into rendered packaging files, declare it through `PERSIST_STATE_KEYS` in `package.conf`.
- Hooks should not edit generated `PKGBUILD` files directly.

### Generated packaging files
- Do not hand-maintain `PKGBUILD` in package directories.
- Do not commit generated `.SRCINFO`.
- If you need to debug generated packaging files, inspect the temporary workspace created by `run_update` rather than creating permanent repo files.

### `.install` files and systemd services
- Prefer `INSTALL_MODE=generated` for ordinary service packages.
- Use static files under `files/` when install messaging is package-specific.
- If a package ships a service, keep User Level vs System Level guidance explicit.
- User services belong under `/usr/lib/systemd/user/`.
- If service behavior changes, update the related generated/static install guidance too.

### Naming, types, and data shapes
- Package directories should be kebab-case and match `PKGNAME`.
- Common dynamic state variables use `RESOLVED_*` and `STATE_*` prefixes.
- This repo is Bash-first; there is no typed-language standard config.
- Prefer simple shell data shapes: strings, arrays, and boolean flags via `true` / `false`.

### Error handling and security
- Fail fast on invalid input or missing required files.
- Validate package names and paths; reject `..` and unexpected characters.
- Use safe escaping such as `printf %q` when building shell command strings.
- Check prerequisites for external tools like `curl`, `jq`, `makepkg`, `updpkgsums`, and `git` when relevant.
- Build as non-root `builder`.
- Default to dry-run workflows for local validation.

## Repo-specific gotchas
- Upstream state resolution may use GitHub API or release-page scraping fallback when API access is unavailable.
- Package updates compare against the current AUR repo, so packaging-only changes may bump `pkgrel` even when the upstream version is unchanged.
- AUR sync tracks managed outputs via `.aur-managed-files` and preserves other unmanaged files.
- `files/` assets are copied into temporary workspaces by basename; avoid basename collisions within one package.
- Existing AUR repos may contain extra unmanaged files; the current sync logic preserves them.

## When editing CI or automation
- Preserve the discovery -> resolve/render/build -> publish structure.
- Do not make build steps run as root.
- Be careful with secrets: `AUR_SSH_PRIVATE_KEY`, `AUR_USERNAME`, `AUR_EMAIL`.
- Prefer changes in `scripts/` over adding logic to workflow YAML.

## When adding or removing packages
- Create a new directory matching `PKGNAME`.
- Add `package.conf`.
- Add `hooks.sh` only if the built-in upstream resolvers are insufficient.
- Add `files/` only for static assets such as service units, licenses, or static `.install` scripts.
- Update the `README.md` package table.
- When removing a package, remove its directory and README entry together.

## Preferred agent behavior
- Read the docs before making structural changes.
- Verify one package at a time unless the user asks for a broader sweep.
- Prefer minimal diffs over cleanup-only churn.
- Do not assume generic test or lint tooling exists.
- If asked to “run tests”, clarify that package-level dry-run/build verification is the real test surface here.
