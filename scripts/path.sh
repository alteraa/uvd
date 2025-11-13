#!/bin/sh
# PATH management functions

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
