# Install acme.sh and (optionally) issue the first Let's Encrypt cert via
# webroot HTTP-01.  acme.sh installs a cron entry for renewal automatically.

setup_ssl() {
    install -d -m 0755 /ewomail/acme
    install -d -m 0755 /ewomail/www/default/.well-known/acme-challenge
    chown -R www-data:www-data /ewomail/www/default/.well-known

    if [[ ! -x /root/.acme.sh/acme.sh ]]; then
        # Clone the repo (--depth 1 keeps it tiny) and run the in-tree
        # installer. This is more predictable than piping get.acme.sh,
        # which historically had drift in its bootstrap flag names.
        local tmp; tmp=$(mktemp -d)
        if ! run_quiet git clone --depth 1 https://github.com/acmesh-official/acme.sh.git "${tmp}/acme.sh"; then
            ui_err "Failed to clone acme.sh repository; check outbound HTTPS."
            rm -rf "${tmp}"
            return 1
        fi
        # acme.sh's installer auto-creates ~/.acme.sh/acme.sh and a cron entry.
        run bash "${tmp}/acme.sh/acme.sh" --install \
            --home /root/.acme.sh \
            --accountemail "${EWO_ADMIN_EMAIL}"
        rm -rf "${tmp}"
    fi
    if [[ ! -x /root/.acme.sh/acme.sh ]]; then
        ui_err "acme.sh installation reported success but /root/.acme.sh/acme.sh is missing."
        return 1
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
        # try-reload-or-restart starts a stopped unit or reloads a running one
        # — important here because postfix/dovecot aren't started until the
        # next step. `|| true` per command so a single failure doesn't abort.
        run /root/.acme.sh/acme.sh --install-cert -d "${EWO_MAIL_HOST}" \
            --key-file       /etc/ssl/ewomail/private/privkey.pem \
            --fullchain-file /etc/ssl/ewomail/fullchain.pem \
            --reloadcmd      "systemctl try-reload-or-restart nginx 2>/dev/null || true; systemctl try-reload-or-restart postfix 2>/dev/null || true; systemctl try-reload-or-restart dovecot 2>/dev/null || true"
        ui_ok "Let's Encrypt certificate issued for ${EWO_MAIL_HOST}"
    else
        ui_warn "Could not obtain a Let's Encrypt certificate now (DNS or rate limit?)."
        ui_warn "Self-signed cert is active. Re-issue from the SSL panel once DNS is correct."
    fi
}
