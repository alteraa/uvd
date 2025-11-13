#!/bin/sh
# Main entry point and orchestration

set -u

# Source all modules
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/utils.sh"
. "$SCRIPT_DIR/config.sh"
. "$SCRIPT_DIR/path.sh"
. "$SCRIPT_DIR/installer.sh"

usage() {
    cat <<EOF
uv-installer.sh

The installer for uv 0.9.9

This script unpacks and installs uv binaries to:

    \$XDG_BIN_HOME
    \$XDG_DATA_HOME/../bin
    \$HOME/.local/bin

USAGE:
    uv-installer.sh ARCHIVE_FILE [OPTIONS]

ARGUMENTS:
    ARCHIVE_FILE        Path to pre-downloaded uv archive (required)

OPTIONS:
    -v, --verbose       Enable verbose output
    -q, --quiet         Disable progress output
    --no-modify-path    Don't configure PATH
    -h, --help          Print help information
EOF
}

download_binary_and_run_installer() {
    need_cmd uname
    need_cmd mktemp
    need_cmd chmod
    need_cmd mkdir
    need_cmd rm
    need_cmd tar
    need_cmd grep
    need_cmd cat

    local _archive_file=""
    for arg in "$@"; do
        case "$arg" in
            --help)
                usage
                exit 0
                ;;
            --quiet)
                PRINT_QUIET=1
                ;;
            --verbose)
                PRINT_VERBOSE=1
                ;;
            --no-modify-path)
                say "--no-modify-path has been deprecated; please set UV_NO_MODIFY_PATH=1 in the environment"
                NO_MODIFY_PATH=1
                ;;
            *.tar.gz)
                _archive_file="$arg"
                ;;
            *)
                OPTIND=1
                if [ "${arg%%--*}" = "" ]; then
                    err "unknown option $arg"
                fi
                while getopts :hvq sub_arg "$arg"; do
                    case "$sub_arg" in
                        h)
                            usage
                            exit 0
                            ;;
                        v)
                            PRINT_VERBOSE=1
                            ;;
                        q)
                            PRINT_QUIET=1
                            ;;
                        *)
                            err "unknown option -$OPTARG"
                            ;;
                    esac
                done
                ;;
        esac
    done

    if [ -z "$_archive_file" ]; then
        err "archive file is required. Use download-uv.sh to download first."
    fi

    local _arch="x86_64-unknown-linux-gnu"
    local _artifact_name="uv-x86_64-unknown-linux-gnu.tar.gz"
    local _zip_ext=".tar.gz"
    local _bins="uv uvx"
    local _bins_js_array='"uv","uvx"'
    local _libs=""
    local _libs_js_array=""
    local _staticlibs=""
    local _staticlibs_js_array=""

    RECEIPT="$(echo "$RECEIPT" | sed s/'"CARGO_DIST_BINS"'/"$_bins_js_array"/)"
    RECEIPT="$(echo "$RECEIPT" | sed s/'"CARGO_DIST_DYLIBS"'/"$_libs_js_array"/)"
    RECEIPT="$(echo "$RECEIPT" | sed s/'"CARGO_DIST_STATICLIBS"'/"$_staticlibs_js_array"/)"

    if [ ! -f "$_archive_file" ]; then
        err "archive file not found: $_archive_file"
    fi

    local _dir
    _dir="$(ensure mktemp -d)" || return 1

    say "using archive: $_archive_file" 1>&2

    ensure tar xf "$_archive_file" --strip-components 1 -C "$_dir"

    install "$_dir" "$_bins" "$_libs" "$_staticlibs" "$_arch" "$@"
    local _retval=$?
    if [ "$_retval" != 0 ]; then
        return "$_retval"
    fi

    ignore rm -rf "$_dir"

    if [ "$INSTALL_UPDATER" = "1" ]; then
        if ! mkdir -p "$RECEIPT_HOME"; then
            err "unable to create receipt directory at $RECEIPT_HOME"
        else
            echo "$RECEIPT" > "$RECEIPT_HOME/$APP_NAME-receipt.json"
            local _retval=$?
        fi
    else
        local _retval=0
    fi

    return "$_retval"
}

download_binary_and_run_installer "$@" || exit 1
