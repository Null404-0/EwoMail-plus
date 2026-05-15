# Configures a dedicated PHP-FPM pool for the EwoMail web stack.

setup_php_fpm() {
    local pool_dir="/etc/php/${EWO_PHP_VER}/fpm/pool.d"
    # Disable the default www pool: nothing else on the machine uses PHP.
    if [[ -f "${pool_dir}/www.conf" ]]; then
        run mv "${pool_dir}/www.conf" "${pool_dir}/www.conf.disabled"
    fi
    render_template "${INSTALLER_DIR}/templates/php-fpm/ewomail.conf" "${pool_dir}/ewomail.conf"

    # php.ini tweaks for mail web apps (only the FPM ini).
    local fpm_ini="/etc/php/${EWO_PHP_VER}/fpm/php.ini"
    sed -i \
        -e 's/^;\?upload_max_filesize\s*=.*/upload_max_filesize = 64M/' \
        -e 's/^;\?post_max_size\s*=.*/post_max_size = 64M/' \
        -e 's/^;\?memory_limit\s*=.*/memory_limit = 256M/' \
        -e 's/^;\?expose_php\s*=.*/expose_php = Off/' \
        -e "s|^;\?date.timezone\s*=.*|date.timezone = UTC|" \
        "${fpm_ini}"
    ui_ok "PHP-FPM pool installed at ${pool_dir}/ewomail.conf"
}
