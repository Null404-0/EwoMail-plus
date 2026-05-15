# Final summary: extract DKIM TXT, print required DNS records, write
# credentials file with restrictive permissions.

write_credentials_file() {
    local key_file="/ewomail/dkim/${EWO_DOMAIN}.pem"
    local dkim_txt=""
    if [[ -f "${key_file}" ]]; then
        dkim_txt=$(openssl rsa -in "${key_file}" -pubout 2>/dev/null \
            | sed -e '/-----/d' | tr -d '\n')
        dkim_txt="v=DKIM1; k=rsa; p=${dkim_txt}"
    fi
    EWO_DKIM_TXT="${dkim_txt}"
    export EWO_DKIM_TXT

    install -d -m 0700 "${EWOMAIL_PREFIX}"
    umask 077
    cat > "${CREDENTIALS_FILE}" <<EOF
# EwoMail-plus credentials — generated at $(date -Iseconds)
# Keep this file secret. chmod 600.

[mail]
domain                = ${EWO_DOMAIN}
mail_host             = ${EWO_MAIL_HOST}
public_ip             = ${EWO_PUBLIC_IP:-unknown}

[web]
webmail_url           = https://${EWO_MAIL_HOST}/
admin_url             = https://${EWO_MAIL_HOST}/${EWO_ADMIN_PATH}/
adminer_url           = https://${EWO_MAIL_HOST}/${EWO_DB_PATH}/   (enabled=${EWO_DB_ADMIN_ENABLED})

[admin]
username              = admin
password              = ${EWO_ADMIN_PWD}

[mariadb]
root_password         = ${EWO_MYSQL_ROOT_PWD}
ewomail_db            = ewomail
ewomail_db_user       = ewomail
ewomail_db_password   = ${EWO_MYSQL_EWOMAIL_PWD}

[dns]
A      mail   ${EWO_PUBLIC_IP:-<server-ipv4>}
MX     @      mail.${EWO_DOMAIN}.   priority 10
TXT    @      "v=spf1 mx ~all"
TXT    _dmarc "v=DMARC1; p=quarantine; rua=mailto:postmaster@${EWO_DOMAIN}"
TXT    dkim._domainkey   "${EWO_DKIM_TXT}"
PTR    ${EWO_PUBLIC_IP:-<ipv4>} → mail.${EWO_DOMAIN}   (configure at your VPS provider)
EOF
    chmod 0600 "${CREDENTIALS_FILE}"
    ui_ok "Credentials written to ${CREDENTIALS_FILE} (mode 600)"
}

print_summary() {
    cat <<EOF

${UI_GREEN}${UI_BOLD}══════════════════════════════════════════════════════════════════════════
                       Installation complete
══════════════════════════════════════════════════════════════════════════${UI_RESET}

${UI_BOLD}Webmail${UI_RESET}            ${UI_CYAN}https://${EWO_MAIL_HOST}/${UI_RESET}
${UI_BOLD}Admin panel${UI_RESET}        ${UI_CYAN}https://${EWO_MAIL_HOST}/${EWO_ADMIN_PATH}/${UI_RESET}
${UI_BOLD}Database admin${UI_RESET}     ${UI_CYAN}https://${EWO_MAIL_HOST}/${EWO_DB_PATH}/${UI_RESET}    (enabled=${EWO_DB_ADMIN_ENABLED})

${UI_BOLD}Admin login${UI_RESET}        admin / ${UI_YELLOW}${EWO_ADMIN_PWD}${UI_RESET}

${UI_BOLD}Credentials file${UI_RESET}   ${CREDENTIALS_FILE}    (mode 0600, root only)
${UI_BOLD}Install log${UI_RESET}        ${LOG_FILE}

${UI_BOLD}${UI_YELLOW}DNS records to publish on ${EWO_DOMAIN}:${UI_RESET}

  A       mail                          ${EWO_PUBLIC_IP:-<your-ipv4>}
  MX      @                             mail.${EWO_DOMAIN}.    (priority 10)
  TXT     @                             "v=spf1 mx ~all"
  TXT     _dmarc                        "v=DMARC1; p=quarantine; rua=mailto:postmaster@${EWO_DOMAIN}"
  TXT     dkim._domainkey               "${EWO_DKIM_TXT}"

  PTR     ${EWO_PUBLIC_IP:-<ipv4>} → mail.${EWO_DOMAIN}    (set this in your VPS provider's panel)

${UI_DIM}Tip:  run  ${UI_BOLD}dig +short TXT dkim._domainkey.${EWO_DOMAIN}${UI_RESET}${UI_DIM}  after publishing to verify.${UI_RESET}
EOF
}
