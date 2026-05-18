# AGENTS.md

## Purpose
- This repo is an Arch Linux AUR package monorepo.
- Source-of-truth PackageSpec v1 definitions live in `package.toml`, with optional `hooks.sh` and optional `files/` assets.
- `PKGBUILD` and `.SRCINFO` are generated only in temporary workspaces during local runs and CI.
- Prefer small, package-scoped changes over broad cleanup.
- Do not introduce new tooling or languages unless the user asks.

## Read first
- `README.md`
- `docs/CONTRIBUTING.md`
- `docs/INTEGRATION.md`
- `.github/workflows/aur-publish.yml`
- `.github/workflows/package-test.yml`
- `.github/workflows/build-binary-releases.yml`
- `scripts/ci_manager.sh`
- `scripts/auto_update.sh`
- `scripts/test_package.sh`
- `scripts/lib/`

## Repository facts and local rules
- No Cursor rules were found in `.cursor/rules/` or `.cursorrules`.
- No Copilot instructions were found in `.github/copilot-instructions.md`.
- CI auto-discovers package directories by locating PackageSpec v1 `package.toml` files.
- Scheduled AUR publishing first runs upstream-only update detection and then dispatches only changed package jobs.
- The current package state baseline comes from the AUR repo, not from this monorepo.
- Keep workflow YAML thin; most behavior belongs in `scripts/`.
- Build steps must run as the non-root `builder` user.

## Repository workflow
- Main flow: discover packages -> detect upstream changes -> read AUR state -> resolve upstream -> render temporary `PKGBUILD` -> refresh checksums -> generate `.SRCINFO` -> build -> publish to AUR.
- Validation flow: discover packages -> resolve upstream -> render temporary `PKGBUILD` -> build -> install package in a container -> run smoke checks.
- Main entrypoints: `scripts/ci_manager.sh discover`, `scripts/ci_manager.sh detect-updates`, `scripts/ci_manager.sh preflight <pkgname-or-path>`, `scripts/ci_manager.sh run-publish <pkgname-or-path> ...`, `scripts/ci_manager.sh run-test <pkgname-or-path>`, `scripts/ci_manager.sh build-binary-release <pkgname-or-path> ...`, `scripts/auto_update.sh <pkgname-or-path> ...`, `scripts/test_package.sh <pkgname-or-path>`
- When touching update logic, inspect `scripts/auto_update.sh`, the relevant files under `scripts/lib/`, and any package-local `hooks.sh`.

## Framework contract rules
- Treat package definitions as a stable contract. `package.toml` is the current PackageSpec v1 frontend: strict TOML declarative data plus explicit extension points, not a programming language.
- Prefer mechanism over solution: add reusable framework components such as upstream resolvers, packaging templates, artifact producers, install/service renderers, validation primitives, or publishers instead of package-specific workflow/script branches.
- Prefer composition over integration: packages should combine independent components (`template`, `[upstream]`, `[install]`, `[service]`, `[binary_release]`, `[tests]`) rather than opt into monolithic custom flows.
- Keep package behavior package-local. Root manifests, if introduced, may only control discovery scope such as `packages/*/spec.yml`; they must not hold package behavior or become a second source of truth.
- Keep component boundaries sharp: resolvers resolve upstream state only; binary-release producers create assets only; templates render/build packages only; detectors optimize dispatch only; publishers validate and compare against live AUR state before push.
- Keep hooks narrow. Existing `hooks.sh` should only resolve upstream state; future spec hooks should be phase-specific subprocesses with whitelisted outputs, not sourced code that mutates framework internals.
- Do not allow cross-package imports, remote includes, deep inheritance, loops, conditionals, or arbitrary command execution in package specs. Local files must be declared by role (patch, doc, license, service, wrapper, test asset), not blindly included.
- Version package specs with `spec_version`, normalize package definitions into the same internal model, and fail fast on unsupported major schema versions.

## GitHub Actions failure triage
- When investigating failed Actions, first use `gh run list` and `gh run view <run-id> --log-failed` to identify the exact failed package/job before editing.
- Distinguish package-specific failures from transient infrastructure failures. Treat AUR clone failures, GitHub API timeouts, and network download failures as potentially transient unless repeated.
- For GitHub release asset matching failures, inspect upstream release asset names and compare them against `[upstream.assets.<arch>]` selectors in the affected package.
- Prefer tolerant architecture selectors when upstream naming commonly varies, such as accepting both `arm64` and `aarch64` where appropriate.
- Keep fixes package-scoped unless repeated failures show the shared resolver or CI scripts are at fault.
- After package config changes, run `./scripts/ci_manager.sh run-publish <pkgname-or-path> --dry-run` as the minimum verification.

## Build / lint / test / verification commands

### Environment setup
```bash
sudo ./scripts/ci_manager.sh install
sudo ./scripts/ci_manager.sh setup-user
```

### Preferred verification for one package
```bash
./scripts/ci_manager.sh run-publish <pkgname-or-path> --dry-run
./scripts/ci_manager.sh run-test <pkgname-or-path>
```
- This is the repo's closest equivalent to a standard test command.
- It resolves upstream metadata, renders temporary packaging files, refreshes checksums, generates `.SRCINFO`, and verifies one package build.
- `run-test` is the stronger validation path: it builds the package, installs it, and performs smoke checks against the installed files.

### Mandatory verification before reporting completion
- For every package affected by a change, run both `./scripts/ci_manager.sh run-test <pkgname-or-path>` and `./scripts/ci_manager.sh run-publish <pkgname-or-path> --dry-run` before saying the work is complete.
- For shared script/workflow changes that can affect multiple packages, run those two commands for every package in the affected matrix. If an external infrastructure failure blocks verification, do not claim success; report the exact failing command and failing dependency.
- If build verification is intentionally skipped for metadata-only debugging, say so explicitly and use `--skip-build` only as an additional diagnostic, not as a replacement for the required package validation.
- Record the exact validation commands and outcomes in the final response or PR body.

### Lower-level updater
```bash
bash scripts/auto_update.sh <pkgname-or-path> [--dry-run] [--skip-build]
```
- Prefer the manager wrapper unless you specifically need the lower-level script.

### Lint / format status
- No dedicated linter or formatter config was found (`shellcheck`, `shfmt`, `prettier`, `eslint`, `ruff`, `bats`, `pytest`, etc.).
- Match the surrounding style; keep diffs conservative and package-scoped.

## “Single test” guidance
- There is no unit-test framework in this repo.
- The smallest meaningful verification unit is one package directory.
- When asked to run a single test, prefer `./scripts/ci_manager.sh run-test <pkgname-or-path>` for package validation, or `./scripts/ci_manager.sh run-publish <pkgname-or-path> --dry-run` for publish-path verification.
- Use `--skip-build` only for metadata-only debugging when build verification is intentionally unnecessary.

## Code style guidelines

### General
- Keep edits narrowly scoped to the affected package or script.
- Preserve existing comments unless they are inaccurate or stale.
- Do not rename package directories casually; directory name should match `name` in `package.toml`.
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

### `package.toml` style
- Treat `package.toml` as the PackageSpec v1 source of truth.
- Set `spec_version = 1` in every package definition.
- Keep fields declarative and grouped by component: top-level metadata, `[upstream]`, `[package]`, `[build]`, `[files]`, `[install]`, `[service]`, `[tests]`, and optional `[binary_release]`.
- Prefer explicit arrays like `arches = ["x86_64"]`, `depends = []`, `licenses = ["MIT"]`.
- Template selection should be declarative: top-level `template = "..."` and `[upstream] type = "..."`.
- For GitHub-backed packages, use `[upstream] repo = "owner/name"`, `tag_prefix`, and `[upstream.assets.<arch>]` fields.
- If install smoke checks need package-specific assertions, use `[tests] paths`, `[tests] executables`, and `[tests] commands`.
- Prefer package-local static files under `files/` over embedding large blobs in scripts.
- Do not repeat binary packaging in `desc`; `-bin` in `name` is enough.
- Architecture-specific `source_rename` values should include the architecture in the rendered filename.

### Template / hook boundaries
- Keep ordinary packages template-only.
- Use `hooks.sh` only for special upstream resolution or genuinely exceptional packaging behavior.
- `resolve_upstream_state()` should set `RESOLVED_VERSION` and optional `RESOLVED_SOURCE_URL_*` / `STATE_*` values.
- If hook state must persist into rendered packaging files, declare it through `[state] persist` in `package.toml`.
- Hooks should not edit generated `PKGBUILD` files directly.

### Generated packaging files
- Do not hand-maintain `PKGBUILD` in package directories.
- Do not commit generated `.SRCINFO`.
- If you need to debug generated packaging files, inspect the temporary workspace created by `run-publish` rather than creating permanent repo files.

### `.install` files and systemd services
- Prefer `[install] mode = "generated"` for ordinary service packages.
- Use static files under `files/` when install messaging is package-specific.
- If a package ships a service, keep User Level vs System Level guidance explicit.
- User services belong under `/usr/lib/systemd/user/`.
- If service behavior changes, update the related generated/static install guidance too.

### Naming, types, and data shapes
- Package directories should be kebab-case and match PackageSpec `name`; versioned library package names may include dots when that matches Arch convention.
- Prefer kebab-case `ci_manager.sh` commands in docs and workflows; snake_case command names are compatibility aliases only.
- Use consistent user-facing terms: package validation, smoke checks, publish path, and binary-release asset.
- Common dynamic state variables use `RESOLVED_*` and `STATE_*` prefixes.
- This repo is Bash-first internally, but package specs use strict TOML parsed with Python standard-library `tomllib`.
- Prefer simple TOML data shapes: strings, arrays, and booleans.

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
- Update detector state under `.update-state/` is a cache optimization only; AUR state remains the authoritative publish baseline.
- AUR sync tracks managed outputs via `.aur-managed-files` and preserves other unmanaged files.
- `files/` assets are copied into temporary workspaces by basename; avoid basename collisions within one package.
- Existing AUR repos may contain extra unmanaged files; the current sync logic preserves them.

## When editing CI or automation
- Preserve the discovery -> resolve/render/build -> publish structure.
- Do not make build steps run as root.
- Be careful with secrets: `AUR_SSH_PRIVATE_KEY`, `AUR_USERNAME`, `AUR_EMAIL`.
- Prefer changes in `scripts/` over adding logic to workflow YAML.

## When adding or removing packages
- Create a new `packages/<pkgname>/` directory matching PackageSpec `name`.
- Add `package.toml`.
- Add `hooks.sh` only if the built-in upstream resolvers are insufficient.
- Add `files/` only for static assets such as service units, licenses, or static `.install` scripts.
- Update the `README.md` package table.
- When removing a package, remove its `packages/<pkgname>/` directory and README entry together.

## Preferred agent behavior
- Read the docs before making structural changes.
- Verify one package at a time unless the user asks for a broader sweep.
- Prefer minimal diffs over cleanup-only churn.
- Do not assume generic test or lint tooling exists.
- If asked to “run tests”, clarify that package-level dry-run/build verification is the real test surface here.
