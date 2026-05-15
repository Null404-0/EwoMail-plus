# Install acme.sh and (optionally) issue the first Let's Encrypt cert via
# webroot HTTP-01.  acme.sh installs a cron entry for renewal automatically.

setup_ssl() {
    install -d -m 0755 /ewomail/acme
    install -d -m 0755 /ewomail/www/default/.well-known/acme-challenge
    chown -R www-data:www-data /ewomail/www/default/.well-known

    if [[ ! -x /root/.acme.sh/acme.sh ]]; then
        local tmp; tmp=$(mktemp -d)
        if ! curl -fsSL https://get.acme.sh -o "${tmp}/install.sh" >>"${LOG_FILE}" 2>&1; then
            ui_warn "Failed to fetch get.acme.sh from primary URL, trying mirror …"
            curl -fsSL https://raw.githubusercontent.com/acmesh-official/acme.sh/master/acme.sh \
                -o "${tmp}/install.sh" >>"${LOG_FILE}" 2>&1
        fi
        run bash "${tmp}/install.sh" --install-online --home /root/.acme.sh --accountemail "${EWO_ADMIN_EMAIL}"
        rm -rf "${tmp}"
    fi
    run /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ui_ok "acme.sh installed at /root/.acme.sh (auto-renewal via cron)"

    if [[ "${EWO_LE_REQUEST}" != "yes" ]]; then
        ui_info "Skipping Let's Encrypt issuance (will fall back to self-signed cert)."
        return 0
    fi

    # Need nginx up briefly so the webroot challenge works.
    run systemctl restart nginx
    sleep 2
    if /root/.acme.sh/acme.sh --issue \
        -d "${EWO_MAIL_HOST}" \
        -w /ewomail/www/default \
        --server letsencrypt \
        >>"${LOG_FILE}" 2>&1; then
        run /root/.acme.sh/acme.sh --install-cert -d "${EWO_MAIL_HOST}" \
            --key-file       /etc/ssl/ewomail/private/privkey.pem \
            --fullchain-file /etc/ssl/ewomail/fullchain.pem \
            --reloadcmd      "systemctl reload nginx; systemctl reload postfix; systemctl reload dovecot"
        ui_ok "Let's Encrypt certificate issued for ${EWO_MAIL_HOST}"
    else
        ui_warn "Could not obtain a Let's Encrypt certificate now (DNS or rate limit?)."
        ui_warn "Self-signed cert is active. Re-run from the panel once DNS is correct."
    fi
}
