# Nginx: single 80/443 vhost on mail.<domain> with random paths for admin & db.
#   /                       → SnappyMail
#   /<EWO_ADMIN_PATH>/      → ewomail-admin
#   /<EWO_DB_PATH>/         → Adminer (only present when enabled)

setup_nginx() {
    install -d -m 0755 /etc/nginx/snippets
    install -d -m 0755 /etc/nginx/conf.d
    install -d -m 0755 /etc/nginx/sites-available
    install -d -m 0755 /etc/nginx/sites-enabled

    render_template "${INSTALLER_DIR}/templates/nginx/nginx.conf"           /etc/nginx/nginx.conf
    render_template "${INSTALLER_DIR}/templates/nginx/snippets/php.conf"    /etc/nginx/snippets/ewomail-php.conf
    render_template "${INSTALLER_DIR}/templates/nginx/snippets/security.conf" /etc/nginx/snippets/ewomail-security.conf
    render_template "${INSTALLER_DIR}/templates/nginx/snippets/ssl.conf"    /etc/nginx/snippets/ewomail-ssl.conf

    render_template "${INSTALLER_DIR}/templates/nginx/ewomail.conf" /etc/nginx/sites-available/ewomail.conf

    # Replace any default site.
    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/ewomail.conf /etc/nginx/sites-enabled/ewomail.conf

    # Optionally drop the Adminer location. Use the same sentinel marker the
    # helper script writes at runtime, so toggling later from the panel is a
    # straightforward in-place insert/delete.
    if [[ "${EWO_DB_ADMIN_ENABLED}" != "yes" ]]; then
        sed -i 's|## EWOMAIL_DB_ENABLED ##|return 404; # EWOMAIL_DB_DISABLED|' \
            /etc/nginx/sites-available/ewomail.conf
    else
        sed -i '/## EWOMAIL_DB_ENABLED ##/d' /etc/nginx/sites-available/ewomail.conf
    fi

    run nginx -t
    ui_ok "Nginx configured (vhost: ${EWO_MAIL_HOST})"
}
