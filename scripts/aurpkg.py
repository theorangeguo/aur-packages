#!/usr/bin/env python3
"""Single-file PackageSpec CLI bootstrap.

This starts as one Python file on purpose: it keeps the AI-editable surface
compact while preserving internal section boundaries that can be split into a
package later. The existing Bash pipeline remains the execution engine for the
high-risk build/publish path; low-risk discovery and validation commands live
here first.
"""

from __future__ import annotations

import re
import shlex
import json
import os
import subprocess
import sys
import tomllib
from pathlib import Path
from typing import Any


SUPPORTED_SPEC_VERSION = 1
VALID_ARCH_RE = re.compile(r"^[A-Za-z0-9_+-]+$")
VALID_ENV_NAME_RE = re.compile(r"^[A-Z_][A-Z0-9_]*$")
VALID_PACKAGE_INPUT_RE = re.compile(r"^[A-Za-z0-9._-]+$")
VALID_PACKAGE_PATH_INPUT_RE = re.compile(r"^packages/[A-Za-z0-9._-]+$")
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
PACKAGE_ROOT = REPO_ROOT / "packages"

ROOT_KEYS = {
    "spec_version",
    "name",
    "template",
    "packaging_repo_url",
    "metadata",
    "upstream",
    "package",
    "build",
    "files",
    "install",
    "service",
    "state",
    "tests",
    "binary_release",
}

TABLE_KEYS = {
    "metadata": {
        "desc",
        "url",
        "licenses",
        "arches",
        "depends",
        "makedepends",
        "checkdepends",
        "optdepends",
        "options",
        "provides",
        "conflicts",
        "validpgpkeys",
    },
    "upstream": {
        "type",
        "repo",
        "repo_user",
        "repo_name",
        "tag_prefix",
        "release_tag_prefix",
        "allow_prerelease",
        "assets",
    },
    "package": {
        "binary_name",
        "binary_source_path",
        "install_bin_path",
        "wrapper_source_path",
        "wrapper_install_path",
        "wrapper_mode",
    },
    "build": {
        "source_rename",
        "source_dir",
        "build_dir",
        "meson_options",
        "run_check",
        "check_args",
        "deb_relocate_usr_local",
        "appimage_appdir_name",
        "appimage_install_dir",
        "desktop_candidates",
        "icon_candidates",
        "desktop_exec_rewrite",
        "desktop_name_rewrite",
    },
    "files": {"local", "patches", "docs", "licenses"},
    "install": {"mode", "hints", "file"},
    "service": {"mode", "scope", "name", "file", "exec", "restart", "restart_sec"},
    "state": {"persist"},
    "tests": {"paths", "executables", "commands"},
    "binary_release": {
        "enabled",
        "template",
        "rev",
        "version_template",
        "tag_prefix",
        "repo",
        "arches",
        "upstream",
        "source_dir",
        "patch_files",
        "makedepends",
        "cargo_fetch_args",
        "cargo_build_args",
        "cargo_check_args",
        "run_check",
        "archive_files",
        "assets",
    },
    "binary_release.upstream": {"type", "repo", "repo_user", "repo_name", "tag_prefix"},
}

ASSET_KEYS = {"selector", "asset_name", "source_rename"}
BINARY_RELEASE_ASSET_KEYS = {"name"}


class SpecError(Exception):
    pass


class CliError(Exception):
    pass


def fail(message: str) -> None:
    raise SpecError(message)


def load_spec(path: str) -> dict[str, Any]:
    spec_path = Path(path)
    if not spec_path.is_file():
        fail(f"PackageSpec file not found: {path}")

    if spec_path.name != "package.toml":
        fail(f"PackageSpec file must be named package.toml: {path}")

    try:
        with spec_path.open("rb") as handle:
            data = tomllib.load(handle)
    except tomllib.TOMLDecodeError as exc:
        fail(f"Invalid TOML in {path}: {exc}")

    if not isinstance(data, dict):
        fail(f"PackageSpec root must be a TOML table: {path}")

    validate_spec(data, path)
    return data


def reject_unknown_keys(table: dict[str, Any], allowed: set[str], context: str) -> None:
    for key in table:
        if key not in allowed:
            fail(f"Unsupported key in {context}: {key}")


def expect_table(data: dict[str, Any], key: str, path: str) -> dict[str, Any]:
    value = data.get(key, {})
    if value == {}:
        return {}
    if not isinstance(value, dict):
        fail(f"{key} must be a TOML table in {path}")
    return value


def expect_nested_table(table: dict[str, Any], key: str, context: str) -> dict[str, Any]:
    value = table.get(key, {})
    if value == {}:
        return {}
    if not isinstance(value, dict):
        fail(f"{context}.{key} must be a TOML table")
    return value


def validate_spec(data: dict[str, Any], path: str) -> None:
    reject_unknown_keys(data, ROOT_KEYS, path)

    version = require_int(data, "spec_version", path)
    if version != SUPPORTED_SPEC_VERSION:
        fail(f"Unsupported spec_version in {path}: {version}")

    require_string(data, "name", path)
    require_string(data, "template", path)
    optional_string(data, "packaging_repo_url", path)

    metadata = require_table(data, "metadata", path)
    reject_unknown_keys(metadata, TABLE_KEYS["metadata"], f"{path} [metadata]")
    require_string(metadata, "desc", f"{path} [metadata]")
    require_string(metadata, "url", f"{path} [metadata]")
    require_string_list(metadata, "licenses", f"{path} [metadata]")
    require_string_list(metadata, "arches", f"{path} [metadata]")
    for key in TABLE_KEYS["metadata"] - {"desc", "url", "licenses", "arches"}:
        optional_string_list(metadata, key, f"{path} [metadata]")

    upstream = require_table(data, "upstream", path)
    reject_unknown_keys(upstream, TABLE_KEYS["upstream"], f"{path} [upstream]")
    require_string(upstream, "type", f"{path} [upstream]")
    optional_repo(upstream, f"{path} [upstream]")
    optional_string(upstream, "tag_prefix", f"{path} [upstream]")
    optional_string(upstream, "release_tag_prefix", f"{path} [upstream]")
    optional_bool(upstream, "allow_prerelease", f"{path} [upstream]")
    validate_arch_tables(expect_nested_table(upstream, "assets", f"{path} [upstream]"), ASSET_KEYS, f"{path} [upstream.assets]")

    for table_name in ("package", "build", "files", "install", "service", "state", "tests"):
        table = expect_table(data, table_name, path)
        reject_unknown_keys(table, TABLE_KEYS[table_name], f"{path} [{table_name}]")

    validate_optional_strings(expect_table(data, "package", path), TABLE_KEYS["package"], f"{path} [package]")

    build = expect_table(data, "build", path)
    for key in ("source_rename", "source_dir", "build_dir", "appimage_appdir_name", "appimage_install_dir", "desktop_exec_rewrite", "desktop_name_rewrite"):
        optional_string(build, key, f"{path} [build]")
    for key in ("meson_options", "check_args", "desktop_candidates", "icon_candidates"):
        optional_string_list(build, key, f"{path} [build]")
    for key in ("run_check", "deb_relocate_usr_local"):
        optional_bool(build, key, f"{path} [build]")

    files = expect_table(data, "files", path)
    for key in TABLE_KEYS["files"]:
        optional_string_list(files, key, f"{path} [files]")

    install = expect_table(data, "install", path)
    optional_string(install, "mode", f"{path} [install]")
    optional_string_list(install, "hints", f"{path} [install]")
    optional_string(install, "file", f"{path} [install]")

    service = expect_table(data, "service", path)
    for key in TABLE_KEYS["service"]:
        optional_string(service, key, f"{path} [service]")

    state = expect_table(data, "state", path)
    optional_string_list(state, "persist", f"{path} [state]")

    tests = expect_table(data, "tests", path)
    for key in TABLE_KEYS["tests"]:
        optional_string_list(tests, key, f"{path} [tests]")

    binary_release = expect_table(data, "binary_release", path)
    reject_unknown_keys(binary_release, TABLE_KEYS["binary_release"], f"{path} [binary_release]")
    optional_bool(binary_release, "enabled", f"{path} [binary_release]")
    for key in ("template", "version_template", "tag_prefix", "repo", "source_dir"):
        optional_string(binary_release, key, f"{path} [binary_release]")
    optional_int_or_string(binary_release, "rev", f"{path} [binary_release]")
    for key in ("arches", "patch_files", "makedepends", "cargo_fetch_args", "cargo_build_args", "cargo_check_args", "archive_files"):
        optional_string_list(binary_release, key, f"{path} [binary_release]")
    optional_bool(binary_release, "run_check", f"{path} [binary_release]")

    br_upstream = expect_nested_table(binary_release, "upstream", f"{path} [binary_release]")
    reject_unknown_keys(br_upstream, TABLE_KEYS["binary_release.upstream"], f"{path} [binary_release.upstream]")
    optional_string(br_upstream, "type", f"{path} [binary_release.upstream]")
    optional_repo(br_upstream, f"{path} [binary_release.upstream]")
    optional_string(br_upstream, "tag_prefix", f"{path} [binary_release.upstream]")

    validate_arch_tables(expect_nested_table(binary_release, "assets", f"{path} [binary_release]"), BINARY_RELEASE_ASSET_KEYS, f"{path} [binary_release.assets]")

    validate_cross_fields(data, path)


def validate_cross_fields(data: dict[str, Any], path: str) -> None:
    metadata = data["metadata"]
    arches = set(metadata["arches"])
    upstream = data["upstream"]
    upstream_assets = upstream.get("assets", {})

    for arch in upstream_assets:
        if arch not in arches:
            fail(f"[upstream.assets.{arch}] is not listed in [metadata] arches in {path}")

    if upstream["type"] == "github-release-assets":
        for arch in arches:
            asset = upstream_assets.get(arch)
            if asset is None:
                fail(f"[upstream.assets.{arch}] is required for github-release-assets in {path}")
            if not asset.get("selector") and not asset.get("asset_name"):
                fail(f"[upstream.assets.{arch}] requires selector or asset_name in {path}")
            if not asset.get("source_rename"):
                fail(f"[upstream.assets.{arch}] requires source_rename in {path}")

    binary_release = data.get("binary_release", {})
    if binary_release.get("enabled"):
        br_arches = set(binary_release.get("arches", []))
        br_assets = binary_release.get("assets", {})
        for arch in br_assets:
            if arch not in br_arches:
                fail(f"[binary_release.assets.{arch}] is not listed in [binary_release] arches in {path}")
        for arch in br_arches:
            asset = br_assets.get(arch)
            if asset is None or not asset.get("name"):
                fail(f"[binary_release.assets.{arch}] name is required when binary_release is enabled in {path}")


def require_table(data: dict[str, Any], key: str, context: str) -> dict[str, Any]:
    if key not in data:
        fail(f"Missing required table in {context}: {key}")
    value = data[key]
    if not isinstance(value, dict):
        fail(f"{key} must be a TOML table in {context}")
    return value


def require_int(data: dict[str, Any], key: str, context: str) -> int:
    if key not in data:
        fail(f"Missing required key in {context}: {key}")
    value = data[key]
    if not isinstance(value, int) or isinstance(value, bool):
        fail(f"{key} must be an integer in {context}")
    return value


def require_string(data: dict[str, Any], key: str, context: str) -> str:
    if key not in data:
        fail(f"Missing required key in {context}: {key}")
    return expect_string(data[key], key, context)


def optional_string(data: dict[str, Any], key: str, context: str) -> str | None:
    if key not in data:
        return None
    return expect_string(data[key], key, context)


def expect_string(value: Any, key: str, context: str) -> str:
    if not isinstance(value, str):
        fail(f"{key} must be a string in {context}")
    if any(ord(char) < 32 for char in value):
        fail(f"{key} must not contain control characters or newlines in {context}")
    return value


def optional_bool(data: dict[str, Any], key: str, context: str) -> bool | None:
    if key not in data:
        return None
    value = data[key]
    if not isinstance(value, bool):
        fail(f"{key} must be a boolean in {context}")
    return value


def optional_int_or_string(data: dict[str, Any], key: str, context: str) -> str | None:
    if key not in data:
        return None
    value = data[key]
    if isinstance(value, bool) or not isinstance(value, (int, str)):
        fail(f"{key} must be an integer or string in {context}")
    return str(value)


def require_string_list(data: dict[str, Any], key: str, context: str) -> list[str]:
    if key not in data:
        fail(f"Missing required key in {context}: {key}")
    return expect_string_list(data[key], key, context)


def optional_string_list(data: dict[str, Any], key: str, context: str) -> list[str] | None:
    if key not in data:
        return None
    return expect_string_list(data[key], key, context)


def expect_string_list(value: Any, key: str, context: str) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        fail(f"{key} must be an array of strings in {context}")
    return value


def validate_optional_strings(table: dict[str, Any], keys: set[str], context: str) -> None:
    for key in keys:
        optional_string(table, key, context)


def optional_repo(table: dict[str, Any], context: str) -> None:
    optional_string(table, "repo", context)
    optional_string(table, "repo_user", context)
    optional_string(table, "repo_name", context)
    if "repo" in table and ("repo_user" in table or "repo_name" in table):
        fail(f"Use either repo or repo_user/repo_name in {context}, not both")
    if ("repo_user" in table) != ("repo_name" in table):
        fail(f"repo_user and repo_name must be set together in {context}")


def validate_arch_tables(assets: dict[str, Any], allowed: set[str], context: str) -> None:
    for arch, table in assets.items():
        if not VALID_ARCH_RE.match(arch):
            fail(f"Unsupported architecture table in {context}: {arch}")
        if not isinstance(table, dict):
            fail(f"{context}.{arch} must be a TOML table")
        reject_unknown_keys(table, allowed, f"{context}.{arch}")
        for key in allowed:
            optional_string(table, key, f"{context}.{arch}")


def arch_suffix(arch: str) -> str:
    return arch.upper().replace("-", "_").replace("+", "_").replace(".", "_")


def split_repo(table: dict[str, Any], context: str) -> tuple[str, str] | None:
    if "repo" in table:
        repo = table["repo"]
        parts = repo.split("/", 1)
        if len(parts) != 2 or not parts[0] or not parts[1]:
            fail(f"repo must use owner/name format in {context}: {repo}")
        return parts[0], parts[1]
    if "repo_user" in table and "repo_name" in table:
        return table["repo_user"], table["repo_name"]
    return None


def shell_scalar(name: str, value: str | int | bool | None) -> str | None:
    if value is None:
        return None
    if isinstance(value, bool):
        rendered = "true" if value else "false"
    else:
        rendered = str(value)
    return f"{name}={shlex.quote(rendered)}"


def shell_array(name: str, values: list[str] | None) -> str | None:
    if values is None:
        return None
    quoted = " ".join(shlex.quote(value) for value in values)
    return f"{name}=({quoted})"


def add_scalar(lines: list[str], name: str, value: str | int | bool | None) -> None:
    if value is None:
        return
    if not VALID_ENV_NAME_RE.match(name):
        fail(f"Invalid generated variable name: {name}")
    line = shell_scalar(name, value)
    if line is not None:
        lines.append(line)


def add_array(lines: list[str], name: str, values: list[str] | None) -> None:
    if values is None:
        return
    if not VALID_ENV_NAME_RE.match(name):
        fail(f"Invalid generated variable name: {name}")
    line = shell_array(name, values)
    if line is not None:
        lines.append(line)


def emit_shell(data: dict[str, Any]) -> str:
    metadata = data["metadata"]
    upstream = data["upstream"]
    package = data.get("package", {})
    build = data.get("build", {})
    files = data.get("files", {})
    install = data.get("install", {})
    service = data.get("service", {})
    state = data.get("state", {})
    tests = data.get("tests", {})
    binary_release = data.get("binary_release", {})
    lines: list[str] = []

    add_scalar(lines, "PACKAGE_SPEC_VERSION", data["spec_version"])
    add_scalar(lines, "PKGNAME", data["name"])
    add_scalar(lines, "PACKAGE_TEMPLATE", data["template"])
    add_scalar(lines, "PACKAGING_REPO_URL", data.get("packaging_repo_url"))

    add_scalar(lines, "PKGDESC", metadata["desc"])
    add_scalar(lines, "URL", metadata["url"])
    add_array(lines, "LICENSES", metadata["licenses"])
    add_array(lines, "ARCHES", metadata["arches"])
    add_array(lines, "DEPENDS", metadata.get("depends", []))
    add_array(lines, "MAKEDEPENDS", metadata.get("makedepends", []))
    add_array(lines, "CHECKDEPENDS", metadata.get("checkdepends", []))
    add_array(lines, "OPTDEPENDS", metadata.get("optdepends", []))
    add_array(lines, "OPTIONS", metadata.get("options", []))
    add_array(lines, "PROVIDES", metadata.get("provides", []))
    add_array(lines, "CONFLICTS", metadata.get("conflicts", []))
    add_array(lines, "VALIDPGPKEYS", metadata.get("validpgpkeys", []))

    add_scalar(lines, "UPSTREAM_TYPE", upstream["type"])
    repo = split_repo(upstream, "[upstream]")
    if repo is not None:
        add_scalar(lines, "UPSTREAM_REPO_USER", repo[0])
        add_scalar(lines, "UPSTREAM_REPO_NAME", repo[1])
    add_scalar(lines, "UPSTREAM_TAG_PREFIX", upstream.get("tag_prefix"))
    add_scalar(lines, "UPSTREAM_RELEASE_TAG_PREFIX", upstream.get("release_tag_prefix"))
    add_scalar(lines, "UPSTREAM_ALLOW_PRERELEASE", upstream.get("allow_prerelease"))

    for arch, asset in upstream.get("assets", {}).items():
        suffix = arch_suffix(arch)
        add_scalar(lines, f"ASSET_SELECTOR_{suffix}", asset.get("selector"))
        add_scalar(lines, f"UPSTREAM_ASSET_NAME_{suffix}", asset.get("asset_name"))
        add_scalar(lines, f"SOURCE_RENAME_{suffix}", asset.get("source_rename"))

    add_scalar(lines, "BINARY_NAME", package.get("binary_name"))
    add_scalar(lines, "BINARY_SOURCE_PATH", package.get("binary_source_path"))
    add_scalar(lines, "INSTALL_BIN_PATH", package.get("install_bin_path"))
    add_scalar(lines, "WRAPPER_SOURCE_PATH", package.get("wrapper_source_path"))
    add_scalar(lines, "WRAPPER_INSTALL_PATH", package.get("wrapper_install_path"))
    add_scalar(lines, "WRAPPER_MODE", package.get("wrapper_mode"))

    add_scalar(lines, "SOURCE_RENAME", build.get("source_rename"))
    add_scalar(lines, "SOURCE_DIR", build.get("source_dir"))
    add_scalar(lines, "BUILD_DIR", build.get("build_dir"))
    add_array(lines, "PATCH_FILES", files.get("patches", []))
    add_array(lines, "MESON_OPTIONS", build.get("meson_options", []))
    add_scalar(lines, "RUN_CHECK", build.get("run_check"))
    add_array(lines, "CHECK_ARGS", build.get("check_args", []))
    add_scalar(lines, "DEB_RELOCATE_USR_LOCAL", build.get("deb_relocate_usr_local"))
    add_scalar(lines, "APPIMAGE_APPDIR_NAME", build.get("appimage_appdir_name"))
    add_scalar(lines, "APPIMAGE_INSTALL_DIR", build.get("appimage_install_dir"))
    add_array(lines, "DESKTOP_CANDIDATES", build.get("desktop_candidates", []))
    add_array(lines, "ICON_CANDIDATES", build.get("icon_candidates", []))
    add_scalar(lines, "DESKTOP_EXEC_REWRITE", build.get("desktop_exec_rewrite"))
    add_scalar(lines, "DESKTOP_NAME_REWRITE", build.get("desktop_name_rewrite"))

    add_array(lines, "LOCAL_FILES", files.get("local", []))
    add_array(lines, "DOC_FILES", files.get("docs", []))
    add_array(lines, "LICENSE_FILES", files.get("licenses", []))

    add_scalar(lines, "INSTALL_MODE", install.get("mode"))
    add_array(lines, "INSTALL_HINTS", install.get("hints", []))
    add_scalar(lines, "INSTALL_FILE", install.get("file"))

    add_scalar(lines, "SERVICE_MODE", service.get("mode"))
    add_scalar(lines, "SERVICE_SCOPE", service.get("scope"))
    add_scalar(lines, "SERVICE_NAME", service.get("name"))
    add_scalar(lines, "SERVICE_FILE", service.get("file"))
    add_scalar(lines, "SERVICE_EXEC", service.get("exec"))
    add_scalar(lines, "SERVICE_RESTART", service.get("restart"))
    add_scalar(lines, "SERVICE_RESTART_SEC", service.get("restart_sec"))

    add_array(lines, "PERSIST_STATE_KEYS", state.get("persist", []))

    add_array(lines, "TEST_PATHS", tests.get("paths", []))
    add_array(lines, "TEST_EXECUTABLES", tests.get("executables", []))
    add_array(lines, "TEST_COMMANDS", tests.get("commands", []))

    add_scalar(lines, "BINARY_RELEASE_ENABLED", binary_release.get("enabled"))
    add_scalar(lines, "BINARY_RELEASE_TEMPLATE", binary_release.get("template"))
    add_scalar(lines, "BINARY_RELEASE_REV", binary_release.get("rev"))
    add_scalar(lines, "BINARY_RELEASE_VERSION_TEMPLATE", binary_release.get("version_template"))
    add_scalar(lines, "BINARY_RELEASE_TAG_PREFIX", binary_release.get("tag_prefix"))
    add_scalar(lines, "BINARY_RELEASE_REPO", binary_release.get("repo"))
    add_array(lines, "BINARY_RELEASE_ARCHES", binary_release.get("arches", []))
    add_scalar(lines, "BINARY_RELEASE_SOURCE_DIR", binary_release.get("source_dir"))
    add_array(lines, "BINARY_RELEASE_PATCH_FILES", binary_release.get("patch_files", []))
    add_array(lines, "BINARY_RELEASE_MAKEDEPENDS", binary_release.get("makedepends", []))
    add_array(lines, "BINARY_RELEASE_CARGO_FETCH_ARGS", binary_release.get("cargo_fetch_args", []))
    add_array(lines, "BINARY_RELEASE_CARGO_BUILD_ARGS", binary_release.get("cargo_build_args", []))
    add_array(lines, "BINARY_RELEASE_CARGO_CHECK_ARGS", binary_release.get("cargo_check_args", []))
    add_scalar(lines, "BINARY_RELEASE_RUN_CHECK", binary_release.get("run_check"))
    add_array(lines, "BINARY_RELEASE_ARCHIVE_FILES", binary_release.get("archive_files", []))

    br_upstream = binary_release.get("upstream", {})
    add_scalar(lines, "BINARY_RELEASE_UPSTREAM_TYPE", br_upstream.get("type"))
    br_repo = split_repo(br_upstream, "[binary_release.upstream]") if br_upstream else None
    if br_repo is not None:
        add_scalar(lines, "BINARY_RELEASE_UPSTREAM_REPO_USER", br_repo[0])
        add_scalar(lines, "BINARY_RELEASE_UPSTREAM_REPO_NAME", br_repo[1])
    add_scalar(lines, "BINARY_RELEASE_UPSTREAM_TAG_PREFIX", br_upstream.get("tag_prefix"))

    for arch, asset in binary_release.get("assets", {}).items():
        add_scalar(lines, f"BINARY_RELEASE_ASSET_{arch_suffix(arch)}", asset.get("name"))

    return "\n".join(lines) + "\n"


def package_definition_path(package_dir: Path) -> Path | None:
    spec_candidate = package_dir / "package.toml"
    legacy_candidate = package_dir / "package.conf"

    if spec_candidate.is_file() and legacy_candidate.is_file():
        raise CliError(f"Package directory must not contain both package.toml and package.conf: {package_dir}")
    if spec_candidate.is_file():
        return spec_candidate
    return None


def package_has_definition(package_dir: Path) -> bool:
    return package_definition_path(package_dir) is not None


def package_path_for_output(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def discover_package_definition_files(package_root: Path = PACKAGE_ROOT) -> list[Path]:
    if not package_root.is_dir():
        return []
    return sorted(package_root.glob("*/package.toml"))


def collect_all_packages() -> list[str]:
    return [package_path_for_output(path.parent) for path in discover_package_definition_files()]


def canonical_package_dir(package_input: str) -> str:
    value = package_input.removeprefix("./")
    if value.startswith("packages/"):
        if not VALID_PACKAGE_PATH_INPUT_RE.fullmatch(value):
            raise CliError(f"Invalid package directory name: {package_input}")
        candidate = REPO_ROOT / value
    else:
        if not VALID_PACKAGE_INPUT_RE.fullmatch(value):
            raise CliError(f"Invalid package directory name: {package_input}")
        candidate = PACKAGE_ROOT / value

    if package_definition_path(candidate) is None:
        raise CliError(f"PackageSpec definition not found in {package_path_for_output(candidate)}")
    return package_path_for_output(candidate)


def git_diff_changed_files(base_ref: str, head_ref: str) -> list[str]:
    for ref, role in ((base_ref, "base"), (head_ref, "head")):
        result = subprocess.run(
            ["git", "rev-parse", "--verify", f"{ref}^{{commit}}"],
            cwd=REPO_ROOT,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if result.returncode != 0:
            raise CliError(f"Unknown discovery {role} ref: {ref}")

    result = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=ACMR", base_ref, head_ref],
        cwd=REPO_ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise CliError(f"Failed to diff changed files between {base_ref} and {head_ref}: {result.stderr.strip()}")
    return [line for line in result.stdout.splitlines() if line]


def discover_changed_packages(base_ref: str, head_ref: str) -> list[str]:
    packages: list[str] = []
    seen: set[str] = set()

    for changed_file in git_diff_changed_files(base_ref, head_ref):
        if changed_file.startswith("scripts/") or changed_file.startswith(".github/workflows/"):
            return collect_all_packages()

        parts = changed_file.split("/")
        if len(parts) < 3 or parts[0] != "packages":
            continue

        candidate = f"packages/{parts[1]}"
        if candidate in seen:
            continue
        if package_has_definition(REPO_ROOT / candidate):
            seen.add(candidate)
            packages.append(candidate)

    return packages


def parse_discovery_args(command: str, args: list[str]) -> tuple[str | None, str | None, str | None]:
    package_filter: str | None = None
    base_ref: str | None = None
    head_ref: str | None = None
    index = 0

    while index < len(args):
        arg = args[index]
        if arg == "--package":
            index += 1
            if index >= len(args):
                raise CliError("Missing value for --package")
            package_filter = args[index]
        elif arg == "--base-ref":
            index += 1
            if index >= len(args):
                raise CliError("Missing value for --base-ref")
            base_ref = args[index]
        elif arg == "--head-ref":
            index += 1
            if index >= len(args):
                raise CliError("Missing value for --head-ref")
            head_ref = args[index]
        else:
            raise CliError(f"Unknown {command} parameter: {arg}")
        index += 1

    if bool(base_ref) != bool(head_ref):
        raise CliError("--base-ref and --head-ref must be provided together")

    return package_filter, base_ref, head_ref


def selected_packages(command: str, args: list[str]) -> list[str]:
    package_filter, base_ref, head_ref = parse_discovery_args(command, args)
    if package_filter:
        return [canonical_package_dir(package_filter)]
    if base_ref and head_ref:
        return discover_changed_packages(base_ref, head_ref)
    return collect_all_packages()


def package_has_binary_release_enabled(package: str) -> bool:
    spec_path = package_definition_path(REPO_ROOT / package)
    if spec_path is None:
        raise CliError(f"PackageSpec definition not found in {package}")
    data = load_spec(str(spec_path))
    return bool(data.get("binary_release", {}).get("enabled", False))


def emit_package_matrix(packages: list[str], label: str) -> None:
    github_output = os.environ.get("GITHUB_OUTPUT")
    if not github_output:
        if packages:
            print("\n".join(packages))
        return

    matrix_json = json.dumps({"package": packages}, separators=(",", ":"))
    with open(github_output, "a", encoding="utf-8") as handle:
        handle.write(f"matrix={matrix_json}\n")
        handle.write(f"has_packages={'true' if packages else 'false'}\n")
    print(f"==> [aurpkg] Discovered {len(packages)} {label}: {json.dumps(packages)}")


def command_discover(args: list[str]) -> int:
    packages = selected_packages("discover", args)
    emit_package_matrix(packages, "packages")
    return 0


def command_discover_binary_releases(args: list[str]) -> int:
    packages = [package for package in selected_packages("discover-binary-releases", args) if package_has_binary_release_enabled(package)]
    emit_package_matrix(packages, "binary release packages")
    return 0


def regex_escape(value: str) -> str:
    return re.escape(value)


def collect_package_names() -> list[str]:
    names: list[str] = []
    seen: set[str] = set()
    for definition_path in discover_package_definition_files():
        for name in (definition_path.parent.name, load_spec(str(definition_path))["name"]):
            if name and name not in seen:
                seen.add(name)
                names.append(name)
    return names


def shared_automation_files() -> list[Path]:
    roots = [REPO_ROOT / "scripts", REPO_ROOT / ".github" / "workflows"]
    suffixes = {".sh", ".py", ".yml", ".yaml"}
    files: list[Path] = []
    for root in roots:
        if not root.is_dir():
            continue
        for path in root.rglob("*"):
            if path.is_file() and path.suffix in suffixes:
                files.append(path)
    return sorted(files)


def command_check_framework_boundaries(args: list[str]) -> int:
    if args:
        raise CliError(f"Unknown check-framework-boundaries parameter: {args[0]}")

    failures: list[str] = []
    package_names = collect_package_names()
    shared_files = shared_automation_files()

    for definition_path in discover_package_definition_files():
        load_spec(str(definition_path))

    for package_name in package_names:
        package_name_pattern = re.compile(rf"(^|[^A-Za-z0-9._-]){regex_escape(package_name)}([^A-Za-z0-9._-]|$)")
        for path in shared_files:
            text = path.read_text(encoding="utf-8", errors="ignore")
            for line_number, line in enumerate(text.splitlines(), start=1):
                if package_name_pattern.search(line):
                    rel = path.relative_to(REPO_ROOT).as_posix()
                    failures.append(f"Package-specific name '{package_name}' found in shared automation: {rel}:{line_number}:{line}")

    branch_patterns = [
        re.compile(r'''case\s+["']?\$\{?PKGNAME\}?'''),
        re.compile(r'''if\s+.*\$\{?PKGNAME\}?.*(=|==|!=)\s*["']?[A-Za-z0-9._+-]+'''),
    ]
    for path in shared_files:
        text = path.read_text(encoding="utf-8", errors="ignore")
        for line_number, line in enumerate(text.splitlines(), start=1):
            if any(pattern.search(line) for pattern in branch_patterns):
                rel = path.relative_to(REPO_ROOT).as_posix()
                failures.append(f"Potential package-name branching found in shared automation: {rel}:{line_number}:{line}")

    if failures:
        for failure in failures:
            print(f"!! ERROR: {failure}", file=sys.stderr)
        print(
            "\nShared automation must stay package-agnostic.\n"
            "Move package-specific behavior into PackageSpec v1 package.toml, package-local hooks.sh, package-local files/, or a new generic framework feature.\n"
            "See docs/PACKAGE_FRAMEWORK.md.",
            file=sys.stderr,
        )
        return 1

    print("Framework boundary check passed.")
    return 0


def command_spec_compat(command: str, args: list[str]) -> int:
    if len(args) != 1:
        print("Usage: aurpkg.py <validate|name|shell> <package.toml>", file=sys.stderr)
        return 2
    data = load_spec(args[0])
    if command == "validate":
        return 0
    if command == "name":
        print(data["name"], end="")
        return 0
    print(emit_shell(data), end="")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("Usage: aurpkg.py <command> [args]", file=sys.stderr)
        return 2

    command = argv[1]
    args = argv[2:]
    try:
        if command in {"validate", "name", "shell"}:
            return command_spec_compat(command, args)
        if command == "discover":
            return command_discover(args)
        if command in {"discover-binary-releases", "discover_binary_releases"}:
            return command_discover_binary_releases(args)
        if command in {"check-framework-boundaries", "check_framework_boundaries"}:
            return command_check_framework_boundaries(args)
        print(f"Unknown command: {command}", file=sys.stderr)
        return 2
    except (SpecError, CliError) as exc:
        print(exc, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
