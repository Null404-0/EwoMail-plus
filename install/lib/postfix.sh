# Postfix: virtual domain/maildir via MySQL, dovecot LMTP, amavis content filter.

setup_postfix() {
    # Render main.cf and master.cf.
    render_template "${INSTALLER_DIR}/templates/postfix/main.cf"      /etc/postfix/main.cf
    render_template "${INSTALLER_DIR}/templates/postfix/master.cf"    /etc/postfix/master.cf

    install -d -m 0750 -o root -g postfix /etc/postfix/mysql
    for f in mysql-mailbox-domains.cf mysql-mailbox-maps.cf \
             mysql-alias-maps.cf mysql-sender-login-maps.cf \
             mysql_bcc_user.cf; do
        render_template "${INSTALLER_DIR}/templates/postfix/mysql/${f}" "/etc/postfix/mysql/${f}"
        chmod 0640 "/etc/postfix/mysql/${f}"
        chown root:postfix "/etc/postfix/mysql/${f}"
    done

    # Vmail user (shared with Dovecot).
    if ! getent group vmail >/dev/null;  then groupadd -g 5000 vmail; fi
    if ! getent passwd vmail >/dev/null; then
        useradd -M -u 5000 -g vmail -s /usr/sbin/nologin -d /ewomail/mail vmail
    fi
    install -d -m 0770 -o vmail -g vmail /ewomail/mail
    install -d -m 0770 -o vmail -g vmail /ewomail/mail/vhosts

    # Hostname. May not be available inside unprivileged containers; ignore
    # the failure and rely on /etc/hostname + /etc/hosts.
    hostnamectl set-hostname "${EWO_MAIL_HOST}" >>"${LOG_FILE}" 2>&1 || \
        echo "${EWO_MAIL_HOST}" > /etc/hostname
    if ! grep -q "${EWO_MAIL_HOST}" /etc/hosts; then
        echo "127.0.1.1 ${EWO_MAIL_HOST} mail" >> /etc/hosts
    fi

    # Generate a default self-signed cert + DH params that Postfix/Dovecot/
    # Nginx can fall back to before Let's Encrypt issues real ones.
    install -d -m 0755 /etc/ssl/ewomail
    install -d -m 0700 /etc/ssl/ewomail/private
    if [[ ! -f /etc/ssl/ewomail/fullchain.pem ]]; then
        openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
            -keyout /etc/ssl/ewomail/private/privkey.pem \
            -out    /etc/ssl/ewomail/fullchain.pem \
            -subj "/CN=${EWO_MAIL_HOST}" >>"${LOG_FILE}" 2>&1
        chmod 600 /etc/ssl/ewomail/private/privkey.pem
    fi
    if [[ ! -f /etc/ssl/ewomail/dh.pem ]]; then
        # 2048 bits is the FFDHE recommendation. Generation is slow on a
        # cold VPS (30-60s); acceptable since this runs only once.
        openssl dhparam -out /etc/ssl/ewomail/dh.pem 2048 >>"${LOG_FILE}" 2>&1
        chmod 644 /etc/ssl/ewomail/dh.pem
    fi

    ui_ok "Postfix configured (main.cf, master.cf, mysql lookup tables)"
}
