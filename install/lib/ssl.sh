# Install acme.sh and (optionally) issue the first Let's Encrypt cert via
# webroot HTTP-01.  acme.sh installs a cron entry for renewal automatically.

# 判断 acme.sh 本地账户里是否已经有该域名的证书（不调任何 LE API），
# 用来在反复重装 / 限流后避开新一轮 --issue。
acme_has_domain_cert() {
    local domain="$1"
    /root/.acme.sh/acme.sh --list --listraw 2>/dev/null | awk -F'|' -v d="${domain}" '
        NR == 1 && $1 ~ /Main_Domain/ { next }
        {
            gsub(/^[ \t]+|[ \t.]+$/, "", $1)
            if ($1 == d) found = 1
        }
        END { exit found ? 0 : 1 }
    '
}

# 把 acme.sh 已经签过的证书部署到 /etc/ssl/ewomail。优先按 ECC 取（acme.sh
# 默认 ECC），取不到再回退 RSA 老路径——兼容老安装。
# 用 try-reload-or-restart 是因为本函数在安装阶段也会被调（postfix/dovecot
# 那时还没起，单纯 reload 会失败）。
install_acme_domain_cert() {
    local domain="$1"

    /root/.acme.sh/acme.sh --install-cert -d "${domain}" --ecc \
        --key-file       /etc/ssl/ewomail/private/privkey.pem \
        --fullchain-file /etc/ssl/ewomail/fullchain.pem \
        --reloadcmd      "systemctl try-reload-or-restart nginx 2>/dev/null || true; systemctl try-reload-or-restart postfix 2>/dev/null || true; systemctl try-reload-or-restart dovecot 2>/dev/null || true" \
        || /root/.acme.sh/acme.sh --install-cert -d "${domain}" \
        --key-file       /etc/ssl/ewomail/private/privkey.pem \
        --fullchain-file /etc/ssl/ewomail/fullchain.pem \
        --reloadcmd      "systemctl try-reload-or-restart nginx 2>/dev/null || true; systemctl try-reload-or-restart postfix 2>/dev/null || true; systemctl try-reload-or-restart dovecot 2>/dev/null || true"
}

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
            ui_err "acme.sh 仓库克隆失败，请检查出口 HTTPS。"
            rm -rf "${tmp}"
            return 1
        fi
        # acme.sh's installer copies acme.sh from CWD via a relative path,
        # so we must cd into the clone first; running by absolute path
        # otherwise fails with "cp: cannot stat 'acme.sh'".
        run bash -c "cd '${tmp}/acme.sh' && ./acme.sh --install --home /root/.acme.sh --accountemail '${EWO_ADMIN_EMAIL}'"
        rm -rf "${tmp}"
    fi
    if [[ ! -x /root/.acme.sh/acme.sh ]]; then
        ui_err "acme.sh 安装显示成功，但 /root/.acme.sh/acme.sh 文件不存在。"
        return 1
    fi
    run /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ui_ok "acme.sh 已安装于 /root/.acme.sh（cron 自动续签）"

    if [[ "${EWO_LE_REQUEST}" != "yes" ]]; then
        ui_info "已跳过 Let's Encrypt 签发，当前使用自签证书。"
        ui_info "DNS 生效后进面板「服务器 → SSL证书」点「申请」一键签发。"
        return 0
    fi

    # Need nginx up briefly so the webroot challenge works.
    run systemctl restart nginx
    sleep 2

    # 反复重装 / 限流期间最重要的一条：装到这步之前如果 acme.sh 本地账户
    # 已经有这张证书了（例如恢复过 /root/.acme.sh），就直接 install 部署，
    # 完全不碰 LE API、不消耗任何配额。
    if acme_has_domain_cert "${EWO_MAIL_HOST}"; then
        run install_acme_domain_cert "${EWO_MAIL_HOST}"
        ui_ok "已复用并部署 ${EWO_MAIL_HOST} 现有 Let's Encrypt 证书"
        return 0
    fi

    if /root/.acme.sh/acme.sh --issue \
        -d "${EWO_MAIL_HOST}" \
        -w /ewomail/www/default \
        --server letsencrypt \
        >>"${LOG_FILE}" 2>&1; then
        run install_acme_domain_cert "${EWO_MAIL_HOST}"
        ui_ok "已为 ${EWO_MAIL_HOST} 签发 Let's Encrypt 证书"
    else
        # --issue 失败的兜底：如果其实有现成证书（罕见——上面已经 check 过；
        # 但 acme.sh 行为在边缘情况下可能让上面漏 check），再尝试部署一次。
        if acme_has_domain_cert "${EWO_MAIL_HOST}" \
           && install_acme_domain_cert "${EWO_MAIL_HOST}" >>"${LOG_FILE}" 2>&1; then
            ui_ok "签发被跳过/限流，但已部署 ${EWO_MAIL_HOST} 现有 Let's Encrypt 证书"
            return 0
        fi
        ui_warn "暂时无法签发 LE 证书（DNS 未生效或被限流？）"
        ui_warn "当前使用自签证书。DNS 生效后从 SSL 面板再签一次即可。"
    fi
}
