#!/bin/sh
# Configuration and global variables

APP_NAME="uv"
APP_VERSION="0.9.9"

if [ -n "${UV_INSTALLER_GHE_BASE_URL:-}" ]; then
    INSTALLER_BASE_URL="$UV_INSTALLER_GHE_BASE_URL"
else
    INSTALLER_BASE_URL="${UV_INSTALLER_GITHUB_BASE_URL:-https://github.com}"
fi

if [ -n "${UV_DOWNLOAD_URL:-}" ]; then
    ARTIFACT_DOWNLOAD_URL="$UV_DOWNLOAD_URL"
elif [ -n "${INSTALLER_DOWNLOAD_URL:-}" ]; then
    ARTIFACT_DOWNLOAD_URL="$INSTALLER_DOWNLOAD_URL"
else
    ARTIFACT_DOWNLOAD_URL="${INSTALLER_BASE_URL}/astral-sh/uv/releases/download/0.9.9"
fi

PRINT_VERBOSE=${UV_PRINT_VERBOSE:-${INSTALLER_PRINT_VERBOSE:-0}}
PRINT_QUIET=${UV_PRINT_QUIET:-${INSTALLER_PRINT_QUIET:-0}}
NO_MODIFY_PATH=${UV_NO_MODIFY_PATH:-${INSTALLER_NO_MODIFY_PATH:-0}}

if [ "${UV_DISABLE_UPDATE:-0}" = "1" ]; then
    INSTALL_UPDATER=0
else
    INSTALL_UPDATER=1
fi

UNMANAGED_INSTALL="${UV_UNMANAGED_INSTALL:-}"
if [ -n "${UNMANAGED_INSTALL}" ]; then
    NO_MODIFY_PATH=1
    INSTALL_UPDATER=0
fi

AUTH_TOKEN="${UV_GITHUB_TOKEN:-}"

read -r RECEIPT <<EORECEIPT
{"binaries":["CARGO_DIST_BINS"],"binary_aliases":{},"cdylibs":["CARGO_DIST_DYLIBS"],"cstaticlibs":["CARGO_DIST_STATICLIBS"],"install_layout":"unspecified","install_prefix":"AXO_INSTALL_PREFIX","modify_path":true,"provider":{"source":"cargo-dist","version":"0.30.2"},"source":{"app_name":"uv","name":"uv","owner":"astral-sh","release_type":"github"},"version":"0.9.9"}
EORECEIPT

INFERRED_HOME=$(get_home)
INFERRED_HOME_EXPRESSION=$(get_home_expression)
RECEIPT_HOME="${XDG_CONFIG_HOME:-$INFERRED_HOME/.config}/uv"
