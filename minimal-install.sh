#!/bin/sh
set -u

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

get_home() {
    if [ -n "${HOME:-}" ]; then
        echo "$HOME"
    elif [ -n "${USER:-}" ]; then
        getent passwd "$USER" | cut -d: -f6
    else
        getent passwd "$(id -un)" | cut -d: -f6
    fi
}

get_home_expression() {
    if [ -n "${HOME:-}" ]; then
        echo '$HOME'
    elif [ -n "${USER:-}" ]; then
        getent passwd "$USER" | cut -d: -f6
    else
        getent passwd "$(id -un)" | cut -d: -f6
    fi
}

INFERRED_HOME=$(get_home)
INFERRED_HOME_EXPRESSION=$(get_home_expression)
RECEIPT_HOME="${XDG_CONFIG_HOME:-$INFERRED_HOME/.config}/uv"

usage() {
    cat <<EOF
uv-installer.sh

The installer for uv 0.9.9

This script fetches the appropriate archive from
https://github.com/astral-sh/uv/releases/download/0.9.9
then unpacks the binaries and installs them to:

    \$XDG_BIN_HOME
    \$XDG_DATA_HOME/../bin
    \$HOME/.local/bin

USAGE:
    uv-installer.sh [OPTIONS]

OPTIONS:
    -v, --verbose       Enable verbose output
    -q, --quiet         Disable progress output
    --no-modify-path    Don't configure PATH
    -h, --help          Print help information
EOF
}

download_binary_and_run_installer() {
    downloader --check
    need_cmd uname
    need_cmd mktemp
    need_cmd chmod
    need_cmd mkdir
    need_cmd rm
    need_cmd tar
    need_cmd grep
    need_cmd cat

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

    local _url="$ARTIFACT_DOWNLOAD_URL/$_artifact_name"
    local _dir
    _dir="$(ensure mktemp -d)" || return 1
    local _file="$_dir/input$_zip_ext"

    say "downloading $APP_NAME $APP_VERSION ${_arch}" 1>&2
    say_verbose "  from $_url" 1>&2
    say_verbose "  to $_file" 1>&2

    ensure mkdir -p "$_dir"

    if ! downloader "$_url" "$_file"; then
        say "failed to download $_url"
        say "this may be a standard network error, but it may also indicate"
        say "that $APP_NAME's release process is not working. When in doubt"
        say "please feel free to open an issue!"
        exit 1
    fi

    ensure tar xf "$_file" --strip-components 1 -C "$_dir"

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

replace_home() {
    local _str="$1"
    if [ -n "${HOME:-}" ]; then
        echo "$_str" | sed "s,$HOME,\$HOME,"
    else
        echo "$_str"
    fi
}

install() {
    local _install_dir
    local _lib_install_dir
    local _receipt_install_dir
    local _env_script_path
    local _install_dir_expr
    local _env_script_path_expr
    local _force_install_dir
    local _install_layout="unspecified"

    if [ -n "${UV_INSTALL_DIR:-}" ]; then
        _force_install_dir="$UV_INSTALL_DIR"
        _install_layout="flat"
    elif [ -n "${CARGO_DIST_FORCE_INSTALL_DIR:-}" ]; then
        _force_install_dir="$CARGO_DIST_FORCE_INSTALL_DIR"
        _install_layout="flat"
    elif [ -n "$UNMANAGED_INSTALL" ]; then
        _force_install_dir="$UNMANAGED_INSTALL"
        _install_layout="flat"
    fi

    if [ -n "${_force_install_dir:-}" ]; then
        _install_dir="$_force_install_dir"
        _lib_install_dir="$_force_install_dir"
        _receipt_install_dir="$_install_dir"
        _env_script_path="$_force_install_dir/env"
        _install_dir_expr="$(replace_home "$_force_install_dir")"
        _env_script_path_expr="$(replace_home "$_force_install_dir/env")"
    fi

    if [ -z "${_install_dir:-}" ]; then
        _install_layout="flat"
        if [ -n "${XDG_BIN_HOME:-}" ]; then
            _install_dir="$XDG_BIN_HOME"
            _lib_install_dir="$_install_dir"
            _receipt_install_dir="$_install_dir"
            _env_script_path="$XDG_BIN_HOME/env"
            _install_dir_expr="$(replace_home "$_install_dir")"
            _env_script_path_expr="$(replace_home "$_env_script_path")"
        fi
    fi

    if [ -z "${_install_dir:-}" ]; then
        _install_layout="flat"
        if [ -n "${XDG_DATA_HOME:-}" ]; then
            _install_dir="$XDG_DATA_HOME/../bin"
            _lib_install_dir="$_install_dir"
            _receipt_install_dir="$_install_dir"
            _env_script_path="$XDG_DATA_HOME/../bin/env"
            _install_dir_expr="$(replace_home "$_install_dir")"
            _env_script_path_expr="$(replace_home "$_env_script_path")"
        fi
    fi

    if [ -z "${_install_dir:-}" ]; then
        _install_layout="flat"
        if [ -n "${INFERRED_HOME:-}" ]; then
            _install_dir="$INFERRED_HOME/.local/bin"
            _lib_install_dir="$INFERRED_HOME/.local/bin"
            _receipt_install_dir="$_install_dir"
            _env_script_path="$INFERRED_HOME/.local/bin/env"
            _install_dir_expr="$INFERRED_HOME_EXPRESSION/.local/bin"
            _env_script_path_expr="$INFERRED_HOME_EXPRESSION/.local/bin/env"
        fi
    fi

    if [ -z "$_install_dir_expr" ]; then
        err "could not find a valid path to install to!"
    fi

    _fish_env_script_path="${_env_script_path}.fish"
    _fish_env_script_path_expr="${_env_script_path_expr}.fish"

    RECEIPT=$(echo "$RECEIPT" | sed "s,AXO_INSTALL_PREFIX,$_receipt_install_dir,")
    RECEIPT=$(echo "$RECEIPT" | sed "s'\"binary_aliases\":{}'{}'")
    RECEIPT=$(echo "$RECEIPT" | sed "s'\"install_layout\":\"unspecified\"'\"install_layout\":\"$_install_layout\"'")
    
    if [ "$NO_MODIFY_PATH" = "1" ]; then
        RECEIPT=$(echo "$RECEIPT" | sed "s'\"modify_path\":true'\"modify_path\":false'")
    fi

    say "installing to $_install_dir"
    ensure mkdir -p "$_install_dir"
    ensure mkdir -p "$_lib_install_dir"

    local _src_dir="$1"
    local _bins="$2"
    local _libs="$3"
    local _staticlibs="$4"
    local _arch="$5"

    for _bin_name in $_bins; do
        local _bin="$_src_dir/$_bin_name"
        ensure mv "$_bin" "$_install_dir"
        ensure chmod +x "$_install_dir/$_bin_name"
        say "  $_bin_name"
    done

    say "everything's installed!"

    case :$PATH: in
        *:$_install_dir:*) NO_MODIFY_PATH=1 ;;
        *) ;;
    esac

    if [ "0" = "$NO_MODIFY_PATH" ]; then
        add_install_dir_to_ci_path "$_install_dir"
        add_install_dir_to_path "$_install_dir_expr" "$_env_script_path" "$_env_script_path_expr" ".profile" "sh"
        exit1=$?
        shotgun_install_dir_to_path "$_install_dir_expr" "$_env_script_path" "$_env_script_path_expr" ".profile .bashrc .bash_profile .bash_login" "sh"
        exit2=$?
        ensure mkdir -p "$INFERRED_HOME/.config/fish/conf.d"
        exit4=$?
        add_install_dir_to_path "$_install_dir_expr" "$_fish_env_script_path" "$_fish_env_script_path_expr" ".config/fish/conf.d/$APP_NAME.env.fish" "fish"
        exit5=$?

        if [ "${exit1:-0}" = 1 ] || [ "${exit2:-0}" = 1 ] || [ "${exit4:-0}" = 1 ] || [ "${exit5:-0}" = 1 ]; then
            say ""
            say "To add $_install_dir_expr to your PATH, either restart your shell or run:"
            say ""
            say "    source $_env_script_path_expr (sh, bash)"
            say "    source $_fish_env_script_path_expr (fish)"
        fi
    fi
}

print_home_for_script() {
    local script="$1"
    local _home
    case "$script" in
        .zsh*)
            if [ -n "${ZDOTDIR:-}" ]; then
                _home="$ZDOTDIR"
            else
                _home="$INFERRED_HOME"
            fi
            ;;
        *)
            _home="$INFERRED_HOME"
            ;;
    esac
    echo "$_home"
}

add_install_dir_to_ci_path() {
    local _install_dir="$1"
    if [ -n "${GITHUB_PATH:-}" ]; then
        ensure echo "$_install_dir" >> "$GITHUB_PATH"
    fi
}

add_install_dir_to_path() {
    local _install_dir_expr="$1"
    local _env_script_path="$2"
    local _env_script_path_expr="$3"
    local _rcfiles="$4"
    local _shell="$5"

    if [ -n "${INFERRED_HOME:-}" ]; then
        local _target
        local _home

        for _rcfile_relative in $_rcfiles; do
            _home="$(print_home_for_script "$_rcfile_relative")"
            local _rcfile="$_home/$_rcfile_relative"

            if [ -f "$_rcfile" ]; then
                _target="$_rcfile"
                break
            fi
        done

        if [ -z "${_target:-}" ]; then
            local _rcfile_relative
            _rcfile_relative="$(echo "$_rcfiles" | awk '{ print $1 }')"
            _home="$(print_home_for_script "$_rcfile_relative")"
            _target="$_home/$_rcfile_relative"
        fi

        local _robust_line=". \"$_env_script_path_expr\""
        local _pretty_line="source \"$_env_script_path_expr\""

        if [ ! -f "$_env_script_path" ]; then
            say_verbose "creating $_env_script_path"
            if [ "$_shell" = "sh" ]; then
                write_env_script_sh "$_install_dir_expr" "$_env_script_path"
            else
                write_env_script_fish "$_install_dir_expr" "$_env_script_path"
            fi
        else
            say_verbose "$_env_script_path already exists"
        fi

        if ! grep -F "$_robust_line" "$_target" > /dev/null 2>/dev/null && \
           ! grep -F "$_pretty_line" "$_target" > /dev/null 2>/dev/null
        then
            if [ -f "$_env_script_path" ]; then
                local _line
                if [ "$_shell" = "fish" ]; then
                    _line="$_pretty_line"
                else
                    _line="$_robust_line"
                fi
                say_verbose "adding $_line to $_target"
                ensure echo "" >> "$_target"
                ensure echo "$_line" >> "$_target"
                return 1
            fi
        else
            say_verbose "$_install_dir already on PATH"
        fi
    fi
}

shotgun_install_dir_to_path() {
    local _install_dir_expr="$1"
    local _env_script_path="$2"
    local _env_script_path_expr="$3"
    local _rcfiles="$4"
    local _shell="$5"

    if [ -n "${INFERRED_HOME:-}" ]; then
        local _found=false
        local _home

        for _rcfile_relative in $_rcfiles; do
            _home="$(print_home_for_script "$_rcfile_relative")"
            local _rcfile_abs="$_home/$_rcfile_relative"

            if [ -f "$_rcfile_abs" ]; then
                _found=true
                add_install_dir_to_path "$_install_dir_expr" "$_env_script_path" "$_env_script_path_expr" "$_rcfile_relative" "$_shell"
            fi
        done

        if [ "$_found" = false ]; then
            add_install_dir_to_path "$_install_dir_expr" "$_env_script_path" "$_env_script_path_expr" "$_rcfiles" "$_shell"
        fi
    fi
}

write_env_script_sh() {
    local _install_dir_expr="$1"
    local _env_script_path="$2"
    ensure cat <<EOF > "$_env_script_path"
#!/bin/sh
case ":\${PATH}:" in
    *:"$_install_dir_expr":*)
        ;;
    *)
        export PATH="$_install_dir_expr:\$PATH"
        ;;
esac
EOF
}

write_env_script_fish() {
    local _install_dir_expr="$1"
    local _env_script_path="$2"
    ensure cat <<EOF > "$_env_script_path"
if not contains "$_install_dir_expr" \$PATH
    set -x PATH "$_install_dir_expr" \$PATH
end
EOF
}

say() {
    if [ "0" = "$PRINT_QUIET" ]; then
        echo "$1"
    fi
}

say_verbose() {
    if [ "1" = "$PRINT_VERBOSE" ]; then
        echo "$1"
    fi
}

warn() {
    if [ "0" = "$PRINT_QUIET" ]; then
        local red
        local reset
        red=$(tput setaf 1 2>/dev/null || echo '')
        reset=$(tput sgr0 2>/dev/null || echo '')
        say "${red}WARN${reset}: $1" >&2
    fi
}

err() {
    if [ "0" = "$PRINT_QUIET" ]; then
        local red
        local reset
        red=$(tput setaf 1 2>/dev/null || echo '')
        reset=$(tput sgr0 2>/dev/null || echo '')
        say "${red}ERROR${reset}: $1" >&2
    fi
    exit 1
}

need_cmd() {
    if ! check_cmd "$1"
    then err "need '$1' (command not found)"
    fi
}

check_cmd() {
    command -v "$1" > /dev/null 2>&1
    return $?
}

ensure() {
    if ! "$@"; then err "command failed: $*"; fi
}

ignore() {
    "$@"
}

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

download_binary_and_run_installer "$@" || exit 1
