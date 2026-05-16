# fail2ban: postfix-sasl + dovecot + sshd + nginx-http-auth jails.

setup_fail2ban() {
    render_template "${INSTALLER_DIR}/templates/fail2ban/jail.local"          /etc/fail2ban/jail.local
    render_template "${INSTALLER_DIR}/templates/fail2ban/postfix-ewomail.conf" /etc/fail2ban/filter.d/postfix-ewomail.conf
    ui_ok "fail2ban 已配置"
}
