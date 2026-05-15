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

    # Optionally drop the Adminer location.
    if [[ "${EWO_DB_ADMIN_ENABLED}" != "yes" ]]; then
        # Mark Adminer disabled in the rendered file by adding a "return 404"
        # in the random db path block. The template includes a sentinel.
        sed -i 's|## EWOMAIL_DB_ENABLED ##|return 404;|' /etc/nginx/sites-available/ewomail.conf
    else
        sed -i 's|## EWOMAIL_DB_ENABLED ##||' /etc/nginx/sites-available/ewomail.conf
    fi

    run nginx -t
    ui_ok "Nginx configured (vhost: ${EWO_MAIL_HOST})"
}
