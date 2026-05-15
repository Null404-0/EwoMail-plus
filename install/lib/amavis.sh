# Amavis + ClamAV + SpamAssassin + DKIM signing via amavis.

setup_amavis() {
    # Domain-specific tuning: Amavis reads /etc/amavis/conf.d/* in order, with
    # 50-user being the user override that we manage.
    render_template "${INSTALLER_DIR}/templates/amavis/50-user" /etc/amavis/conf.d/50-user

    # DKIM key.
    install -d -m 0750 -o amavis -g amavis /ewomail/dkim
    if [[ ! -f /ewomail/dkim/${EWO_DOMAIN}.pem ]]; then
        amavisd-new genrsa "/ewomail/dkim/${EWO_DOMAIN}.pem" 2048 >>"${LOG_FILE}" 2>&1 || \
            openssl genrsa -out "/ewomail/dkim/${EWO_DOMAIN}.pem" 2048 >>"${LOG_FILE}" 2>&1
    fi
    chown amavis:amavis "/ewomail/dkim/${EWO_DOMAIN}.pem"
    chmod 0640 "/ewomail/dkim/${EWO_DOMAIN}.pem"

    # Allow amavis-clamav handshake (Debian quirk).
    if [[ -f /etc/clamav/clamd.conf ]]; then
        sed -i 's|^LocalSocket .*|LocalSocket /var/run/clamav/clamd.ctl|' /etc/clamav/clamd.conf
        adduser clamav amavis >>"${LOG_FILE}" 2>&1 || true
    fi
    # Some Debian 12 installs leave clamav-daemon paused waiting for signatures;
    # kick a fresh signature pull in the background.
    if command -v freshclam >/dev/null; then
        run_quiet systemctl stop clamav-freshclam || true
        run_quiet freshclam --quiet || true
        run_quiet systemctl start clamav-freshclam || true
    fi

    ui_ok "Amavis + ClamAV + SpamAssassin configured; DKIM key generated"
}
