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

    # /ewomail must be world-traversable (0755): www-data and vmail need to
    # reach their subtrees under it. Sensitive children (credentials.txt,
    # /ewomail/dkim/) have their own restrictive perms — see below.
    # /ewomail must be world-traversable (0755): www-data and vmail need to
    # reach their subtrees under it. Sensitive children (credentials.txt,
    # /ewomail/dkim/) have their own restrictive perms — see below.
    install -d -m 0755 "${EWOMAIL_PREFIX}"
    install -m 0600 /dev/null "${CREDENTIALS_FILE}"
    cat > "${CREDENTIALS_FILE}" <<EOF
# EwoMail-plus 凭据文件，生成于 $(date -Iseconds)
# 妥善保管。已设 chmod 600，仅 root 可读。

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
# 注意：粘贴 TXT 值时不要包含外面的引号；大多数 DNS 服务商会自动加。
A      mail              ${EWO_PUBLIC_IP:-<server-ipv4>}
MX     @                 mail.${EWO_DOMAIN}.    优先级 10
TXT    @                 v=spf1 mx ~all
TXT    _dmarc            v=DMARC1; p=quarantine; rua=mailto:postmaster@${EWO_DOMAIN}
TXT    dkim._domainkey   ${EWO_DKIM_TXT}
CNAME  imap              mail.${EWO_DOMAIN}.    (可选别名)
CNAME  smtp              mail.${EWO_DOMAIN}.    (可选别名)
PTR    ${EWO_PUBLIC_IP:-<ipv4>} → mail.${EWO_DOMAIN}    在 VPS 厂商控制台设置
EOF
    chmod 0600 "${CREDENTIALS_FILE}"
    ui_ok "凭据已写入 ${CREDENTIALS_FILE}（仅 root 可读）"
}

print_summary() {
    cat <<EOF

${UI_GREEN}${UI_BOLD}══════════════════════════════════════════════════════════════════════════
                            安 装 完 成
══════════════════════════════════════════════════════════════════════════${UI_RESET}

${UI_BOLD}网页邮件${UI_RESET}           ${UI_CYAN}https://${EWO_MAIL_HOST}/${UI_RESET}
${UI_BOLD}管理后台${UI_RESET}           ${UI_CYAN}https://${EWO_MAIL_HOST}/${EWO_ADMIN_PATH}/${UI_RESET}
${UI_BOLD}数据库管理${UI_RESET}         ${UI_CYAN}https://${EWO_MAIL_HOST}/${EWO_DB_PATH}/${UI_RESET}    (启用=${EWO_DB_ADMIN_ENABLED})

${UI_BOLD}管理员凭据${UI_RESET}         admin / ${UI_YELLOW}${EWO_ADMIN_PWD}${UI_RESET}

${UI_BOLD}凭据文件${UI_RESET}           ${CREDENTIALS_FILE}    (mode 0600，仅 root 可读)
${UI_BOLD}安装日志${UI_RESET}           ${LOG_FILE}

${UI_BOLD}${UI_YELLOW}请在 ${EWO_DOMAIN} 的 DNS 中发布如下记录${UI_RESET}
${UI_DIM}（提示：粘贴 TXT 值时不要带外侧引号——DNS 服务商一般会自动加）${UI_RESET}

  A       mail                          ${EWO_PUBLIC_IP:-<your-ipv4>}
  MX      @                             mail.${EWO_DOMAIN}.            优先级 10
  TXT     @                             v=spf1 mx ~all
  TXT     _dmarc                        v=DMARC1; p=quarantine; rua=mailto:postmaster@${EWO_DOMAIN}
  TXT     dkim._domainkey               ${EWO_DKIM_TXT}

${UI_DIM}可选别名（让客户端可写 imap.${EWO_DOMAIN} / smtp.${EWO_DOMAIN}；如启用，需要在 SSL 面板重新签发包含 SAN 的证书）：${UI_RESET}
  CNAME   imap                          mail.${EWO_DOMAIN}.
  CNAME   smtp                          mail.${EWO_DOMAIN}.

${UI_BOLD}反向解析（重要）${UI_RESET}：${UI_YELLOW}请在你的 VPS 厂商控制台${UI_RESET} 把 ${EWO_PUBLIC_IP:-<ipv4>} 的 PTR 指向 ${EWO_MAIL_HOST}
（不设置 PTR，Gmail / Outlook 大概率拒收你发出的邮件）

${UI_DIM}发布后可执行  ${UI_BOLD}dig +short TXT dkim._domainkey.${EWO_DOMAIN}${UI_RESET}${UI_DIM}  验证。${UI_RESET}
EOF
}
