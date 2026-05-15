# Generates random passwords and random URL paths.

_random_token() {
    # Crockford-ish base32, easy to read out loud, no o/0/i/l.
    local length="${1:-24}" chars='23456789abcdefghjkmnpqrstuvwxyz' out=""
    while (( ${#out} < length )); do
        out+=$(head -c 64 /dev/urandom | tr -dc "${chars}" | head -c $(( length - ${#out} )))
    done
    printf '%s' "${out}"
}

_random_password() {
    local length="${1:-24}"
    # Strong, alphanumeric only (avoid shell-special characters in conf files).
    head -c 256 /dev/urandom \
        | tr -dc 'A-Za-z0-9' \
        | head -c "${length}"
}

generate_credentials() {
    mkdir -p "${STATE_DIR}"
    chmod 700 "${STATE_DIR}"

    EWO_MYSQL_ROOT_PWD="$(_random_password 32)"
    EWO_MYSQL_EWOMAIL_PWD="$(_random_password 28)"
    EWO_ADMIN_PWD="$(_random_password 20)"
    EWO_ADMIN_PATH="adm-$(_random_token 14)"
    EWO_DB_PATH="db-$(_random_token 14)"
    EWO_CODE_KEY="$(_random_password 32)"

    export EWO_MYSQL_ROOT_PWD EWO_MYSQL_EWOMAIL_PWD EWO_ADMIN_PWD
    export EWO_ADMIN_PATH EWO_DB_PATH EWO_CODE_KEY

    ui_ok "Generated random credentials and URL paths"
}

# Renders a template file by replacing every @@KEY@@ with the value of $KEY.
# Whitespace-safe and works for binary-clean inputs.
render_template() {
    local src="$1" dst="$2"
    [[ -f "${src}" ]] || { ui_err "Template missing: ${src}"; return 1; }

    local content
    content=$(cat "${src}")

    # Replace placeholders. Order them so longer keys win.
    local keys=(
        EWO_DOMAIN EWO_MAIL_HOST EWO_ADMIN_EMAIL EWO_PUBLIC_IP
        EWO_MYSQL_ROOT_PWD EWO_MYSQL_EWOMAIL_PWD EWO_ADMIN_PWD
        EWO_ADMIN_PATH EWO_DB_PATH EWO_CODE_KEY
        EWO_OS_VER EWO_OS_CODENAME EWO_PHP_VER EWO_PHP_SOCK
        EWO_PHP_FPM_SERVICE EWO_DB_ADMIN_ENABLED
    )
    for k in "${keys[@]}"; do
        local v="${!k-}"
        # Use a here-doc-style replacement via bash builtin: no shell escaping issues.
        content="${content//@@${k}@@/${v}}"
    done

    printf '%s' "${content}" > "${dst}"
}
