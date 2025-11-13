#!/bin/sh
# Standalone UV downloader script

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/utils.sh"
. "$SCRIPT_DIR/config.sh"

downloader() {
    _snap_curl=0
    if command -v curl > /dev/null 2>&1; then
        _curl_path=$(command -v curl)
        if echo "$_curl_path" | grep "/snap/" > /dev/null 2>&1; then
            _snap_curl=1
        fi
    fi

    if check_cmd curl && [ "$_snap_curl" = "0" ]
    then _dld=curl
    elif check_cmd wget
    then _dld=wget
    elif [ "$_snap_curl" = "1" ]
    then
        say "curl installed with snap cannot be used to install $APP_NAME"
        say "due to missing permissions. Please uninstall it and"
        say "reinstall curl with a different package manager (e.g., apt)."
        exit 1
    else _dld='curl or wget'
    fi

    if [ "$1" = --check ]
    then need_cmd "$_dld"
    elif [ "$_dld" = curl ]; then
        if [ -n "${AUTH_TOKEN:-}" ]; then
            curl -sSfL --header "Authorization: Bearer ${AUTH_TOKEN}" "$1" -o "$2"
        else
            curl -sSfL "$1" -o "$2"
        fi
    elif [ "$_dld" = wget ]; then
        if [ -n "${AUTH_TOKEN:-}" ]; then
            wget --header "Authorization: Bearer ${AUTH_TOKEN}" "$1" -O "$2"
        else
            wget "$1" -O "$2"
        fi
    else err "Unknown downloader"
    fi
}

usage() {
    cat <<EOF
download-uv.sh - Download uv binary archive

USAGE:
    download-uv.sh [OUTPUT_FILE]

ARGUMENTS:
    OUTPUT_FILE    Path where to save the downloaded file (default: ./uv-x86_64-unknown-linux-gnu.tar.gz)

OPTIONS:
    -h, --help     Print help information
EOF
}

main() {
    for arg in "$@"; do
        case "$arg" in
            --help|-h)
                usage
                exit 0
                ;;
        esac
    done

    downloader --check
    need_cmd uname

    local _arch="x86_64-unknown-linux-gnu"
    local _artifact_name="uv-x86_64-unknown-linux-gnu.tar.gz"
    local _output_file="${1:-$_artifact_name}"
    local _url="$ARTIFACT_DOWNLOAD_URL/$_artifact_name"

    say "downloading $APP_NAME $APP_VERSION ${_arch}"
    say_verbose "  from $_url"
    say_verbose "  to $_output_file"

    if ! downloader "$_url" "$_output_file"; then
        err "failed to download $_url"
    fi

    say "downloaded successfully to $_output_file"
}

main "$@"
