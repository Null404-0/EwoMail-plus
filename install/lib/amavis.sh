# Amavis + ClamAV + SpamAssassin + DKIM signing via amavis.

setup_amavis() {
    # Domain-specific tuning: Amavis reads /etc/amavis/conf.d/* in order, with
    # 50-user being the user override that we manage.
    render_template "${INSTALLER_DIR}/templates/amavis/50-user" /etc/amavis/conf.d/50-user

    # DKIM key. Use openssl directly — the amavis binary name varies
    # between Debian versions (amavisd / amavisd-new) and openssl is always
    # present and well-defined.
    install -d -m 0750 -o amavis -g amavis /ewomail/dkim
    if [[ ! -f /ewomail/dkim/${EWO_DOMAIN}.pem ]]; then
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
        ui_info "首次拉取 ClamAV 病毒库（约 300MB，需 3-5 分钟）"
        run_quiet systemctl stop clamav-freshclam || true
        # Stream so the user can see the download progress.
        run_stream freshclam || ui_warn "freshclam 失败；clamav-daemon 启动后可能需要更长时间才可用"
        run_quiet systemctl start clamav-freshclam || true
    fi

    ui_ok "Amavis + ClamAV + SpamAssassin 已配置；DKIM 密钥已生成"
}
