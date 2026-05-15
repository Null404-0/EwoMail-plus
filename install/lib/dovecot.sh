# Dovecot: IMAP / POP3 / LMTP / Sieve via MySQL passdb, virtual mail tree at
# /ewomail/mail/vhosts/<domain>/<user>.

setup_dovecot() {
    # Wipe shipped conf.d to avoid duplicate definitions, then render ours.
    install -d -m 0755 /etc/dovecot
    install -d -m 0755 /etc/dovecot/conf.d
    rm -f /etc/dovecot/conf.d/*.conf 2>/dev/null || true

    render_template "${INSTALLER_DIR}/templates/dovecot/dovecot.conf"           /etc/dovecot/dovecot.conf
    render_template "${INSTALLER_DIR}/templates/dovecot/dovecot-sql.conf.ext"   /etc/dovecot/dovecot-sql.conf.ext

    for f in 10-auth.conf 10-logging.conf 10-mail.conf 10-master.conf 10-ssl.conf \
             15-lda.conf 15-mailboxes.conf 20-imap.conf 20-pop3.conf 20-lmtp.conf \
             20-managesieve.conf 90-sieve.conf 90-quota.conf auth-sql.conf.ext; do
        render_template "${INSTALLER_DIR}/templates/dovecot/conf.d/${f}" "/etc/dovecot/conf.d/${f}"
    done

    chgrp dovecot /etc/dovecot/dovecot-sql.conf.ext
    chmod 0640    /etc/dovecot/dovecot-sql.conf.ext

    install -d -m 0755 -o vmail -g vmail /ewomail/mail/sieve
    ui_ok "Dovecot configured (IMAP/POP3/LMTP/Sieve, MySQL passdb)"
}
