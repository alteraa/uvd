#!/bin/sh
# Installation logic

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
