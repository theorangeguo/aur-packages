#!/usr/bin/env python3
"""Parse PackageSpec v1 TOML and emit the normalized Bash model.

This script is intentionally narrow: TOML is only a frontend. The existing
Bash pipeline remains the execution engine, and this parser emits the same
normalized variables that renderers/resolvers already consume.
"""

from __future__ import annotations

import re
import shlex
import sys
import tomllib
from pathlib import Path
from typing import Any


SUPPORTED_SPEC_VERSION = 1
VALID_ARCH_RE = re.compile(r"^[A-Za-z0-9_+-]+$")
VALID_ENV_NAME_RE = re.compile(r"^[A-Z_][A-Z0-9_]*$")

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


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] not in {"validate", "name", "shell"}:
        print("Usage: package_spec_toml.py <validate|name|shell> <package.toml>", file=sys.stderr)
        return 2

    try:
        data = load_spec(argv[2])
        command = argv[1]
        if command == "validate":
            return 0
        if command == "name":
            print(data["name"], end="")
            return 0
        print(emit_shell(data), end="")
        return 0
    except SpecError as exc:
        print(exc, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
