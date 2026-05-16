# Package Framework Design

This repository is a small packaging framework, not a collection of hand-written AUR package repos. The long-term goal is that adding a package means adding package-scoped declarative inputs, not editing the shared CI or publishing flow for one-off behavior.

## Design goals

- Keep `scripts/` and `.github/workflows/` package-agnostic.
- Keep each package's source of truth in `packages/<pkgname>/package.conf`.
- Use package-local `hooks.sh` only when a generic resolver cannot express upstream discovery.
- Use package-local `files/` for static assets such as service units, wrappers, install snippets, licenses, and examples.
- Promote repeated package-local tricks into framework features before they spread.
- Render `PKGBUILD`, `.SRCINFO`, generated install files, and copied assets only in temporary workspaces.

## Package boundary

Each package owns only this shape:

```text
packages/<pkgname>/
  package.conf      # required, source of truth
  hooks.sh          # optional, upstream resolution escape hatch
  files/            # optional, static package assets
```

Everything else is shared framework code.

## Naming and terminology rules

- Package directories must match `PKGNAME` exactly.
- Prefer kebab-case package names. Versioned library packages may include a dot when that matches Arch naming conventions, such as `wlroots0.20-vmwgfx`.
- Do not repeat binary packaging in `PKGDESC`; `-bin` in `PKGNAME` is enough unless the upstream product name itself contains that wording.
- Architecture-specific source rename fields should include the architecture in the rendered filename, for example `SOURCE_RENAME_X86_64='${pkgname}-${pkgver}-x86_64.tar.gz'`.
- Prefer these user-facing terms:
  - **package validation** for build/install/smoke-check verification
  - **smoke checks** for installed-file and command assertions
  - **publish path** for the AUR staging/commit/push flow
  - **binary-release asset** for repo-built GitHub Release assets consumed by `-bin` packages
- Prefer kebab-case `scripts/ci_manager.sh` command names in docs and workflows. Snake_case names remain compatibility aliases.

Generated AUR outputs must not be committed under `packages/`:

- `PKGBUILD`
- `.SRCINFO`
- generated top-level `.install` files

Static install scripts are allowed when they are intentionally maintained under package-local `files/` and referenced with `INSTALL_MODE=static`.

## Shared pipeline

The shared flow is always:

1. discover package directories by finding `package.conf`
2. load package configuration
3. resolve upstream version and source URLs
4. prepare a temporary workspace
5. render package outputs
6. refresh checksums and generate `.SRCINFO`
7. build as the non-root `builder` user in CI/root paths
8. install the package in the validation environment
9. run smoke checks
10. publish rendered outputs to AUR only after validation passes

Workflows should stay thin and call repository scripts such as `scripts/ci_manager.sh`. They should not gain package-specific jobs, matrices, or shell branches.

## Framework dispatch points

Shared scripts may branch on framework concepts. These are acceptable because packages opt into them declaratively:

| Concept | Field | Examples |
|---|---|---|
| Package renderer | `PACKAGE_TEMPLATE` | `binary-archive`, `deb-repack`, `appimage-desktop`, `source-meson` |
| Upstream resolver | `UPSTREAM_TYPE` | `github-release-assets`, `custom-hook` |
| Install script | `INSTALL_MODE` | `none`, `generated`, `static` |
| Service unit | `SERVICE_MODE` | `none`, `generated`, `static` |
| Service scope | `SERVICE_SCOPE` | `user`, `system` |
| Repo-built artifacts | `BINARY_RELEASE_TEMPLATE` | `source-cargo` |

Shared scripts must not branch on package names.

## Anti-corruption rule

Do not add package-specific logic to `scripts/` or `.github/workflows/`.

Bad:

```bash
if [ "$PKGNAME" = "some-package-bin" ]; then
    # special case
fi
```

Bad:

```yaml
- name: Special package build step
  if: matrix.package == 'packages/some-package-bin'
```

Good:

```bash
PACKAGE_TEMPLATE=binary-archive
UPSTREAM_TYPE=github-release-assets
SERVICE_MODE=static
SERVICE_FILE='files/some-package.service'
```

If a new package cannot be expressed with existing fields, decide whether the need is:

1. a package-local upstream resolution quirk: add `hooks.sh`
2. a repeated upstream pattern: add a generic `UPSTREAM_TYPE`
3. a repeated packaging layout: add or extend a `PACKAGE_TEMPLATE`
4. a one-off static asset: place it under package `files/`

## Hook contract

`hooks.sh` is intentionally an escape hatch, but it should stay narrow.

Preferred hook behavior:

- define `resolve_upstream_state()`
- set `RESOLVED_VERSION`
- set `RESOLVED_SOURCE_URL`, `RESOLVED_SOURCE_URL_X86_64`, `RESOLVED_SOURCE_URL_AARCH64`, etc.
- set `STATE_*` variables when rendered package files need resolved values

Avoid hook behavior that changes rendering or install shape, such as mutating `BINARY_SOURCE_PATH`, `SERVICE_*`, `DOC_FILES`, or template-specific options. If a hook needs to do that, treat it as evidence that the framework is missing a generic field.

When a `STATE_*` value must persist into a rendered `PKGBUILD`, declare it with `PERSIST_STATE_KEYS` in `package.conf`.

## Adding framework features

Add a framework feature when at least one of these is true:

- two packages need the same hook pattern
- a package-specific hook has to mutate rendering/install variables
- a workflow would otherwise need package-specific logic
- a package requires generated files that can be described by stable configuration

Prefer small, declarative fields over broad script rewrites. Keep template changes backward-compatible for existing packages.

## Current known limitations

These are framework limitations, not package-specific exceptions:

- Architecture support is currently centered on `x86_64` and `aarch64` in several helpers.
- `source-cargo` binary release generation currently supports `x86_64` only.
- `hooks.sh` is sourced shell, so discipline and review are required to keep it within the contract.
- Some non-GitHub upstreams still require package-local hooks; repeated patterns should be promoted to resolvers.

## Boundary guard

`scripts/check_framework_boundaries.sh` scans shared automation for package names and obvious package-name branching. It is a safety net, not a complete proof: review still needs to catch upstream-name hardcoding or generic-looking package exceptions. Package names belong under `packages/`, documentation, and generated AUR outputs, not in shared scripts or workflows.

Run it locally before opening PRs that touch automation:

```bash
./scripts/ci_manager.sh check-framework-boundaries
```

The package validation workflow runs the same guard.

## New package checklist

Before adding a package, answer these questions:

1. Can the package be expressed with an existing `PACKAGE_TEMPLATE`?
2. Can upstream be resolved with an existing `UPSTREAM_TYPE`?
3. If `hooks.sh` is needed, does it only resolve upstream state?
4. Are all static assets under package-local `files/`?
5. Are smoke checks declared through `TEST_PATHS`, `TEST_EXECUTABLES`, or `TEST_COMMANDS`?
6. Did you avoid editing workflows for a package-specific reason?
7. Did you update `README.md` when adding or removing a package?

If the answer to any of the framework questions is no, add a generic mechanism first or call out the exception in review.
