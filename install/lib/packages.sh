# Installs system packages from Debian repositories only.

setup_nginx_org_repo() {
    # 把 nginx.org stable 源加进 apt，并 pin 到 priority 900，让 `apt install
    # nginx` 永远走 nginx.org（一般是 1.30.x），不走 Debian 自带的 1.22.1。
    # CVE-2026-42945 的修复在 1.30.1 / 1.31.0 起，所以 1.22 是硬要避免的。
    #
    # 失败处理：之前是静默回退到 Debian 自带，结果用户装完拿到 1.22 自己都
    # 不知道。现在硬失败 —— precheck_nginx_org 已经在 confirm 之前验过可达，
    # 这里再失败说明是 curl/gpg 工具坏了或 keyrings 目录有问题，需要排查。
    if [[ "${EWO_ALLOW_NGINX_OLD:-0}" == "1" ]]; then
        ui_warn "EWO_ALLOW_NGINX_OLD=1：跳过 nginx.org 源配置，将使用 Debian 自带 nginx 1.22"
        return 0
    fi

    install -d -m 0755 /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/nginx.gpg ]]; then
        local attempts=3 i ok=0 tmp_key curl_mode
        tmp_key=$(mktemp)
        for i in 1 2 3; do
            for curl_mode in "-4" ""; do
                if curl -fsSL ${curl_mode} --connect-timeout 10 --max-time 30 \
                        -o "${tmp_key}" \
                        https://nginx.org/keys/nginx_signing.key 2>>"${LOG_FILE}"; then
                    # 校验下载下来的内容确实是 ASCII-armored PGP key
                    if [[ -s "${tmp_key}" ]] && head -1 "${tmp_key}" | grep -q 'BEGIN PGP PUBLIC KEY'; then
                        if gpg --dearmor -o /etc/apt/keyrings/nginx.gpg < "${tmp_key}" 2>>"${LOG_FILE}"; then
                            ok=1; break 2
                        fi
                    fi
                fi
            done
            [[ $i -lt $attempts ]] && {
                ui_dim "nginx.org 密钥获取失败（${i}/${attempts}），${i}s 后重试……"
                sleep $((i * 2))
            }
        done
        rm -f "${tmp_key}"
        if [[ $ok -ne 1 ]]; then
            ui_err "$(printf '获取 nginx.org 签名密钥失败（重试 %s 次都没成功）。\n详细日志见 %s。\n如需用 Debian 自带 1.22 装：EWO_ALLOW_NGINX_OLD=1 ./install.sh\n' "$attempts" "${LOG_FILE}")"
            return 1
        fi
        chmod 0644 /etc/apt/keyrings/nginx.gpg
    fi

    cat > /etc/apt/sources.list.d/nginx-stable.list <<EOF
deb [signed-by=/etc/apt/keyrings/nginx.gpg] https://nginx.org/packages/debian ${EWO_OS_CODENAME} nginx
EOF
    cat > /etc/apt/preferences.d/nginx-stable <<'EOF'
Package: nginx
Pin: origin nginx.org
Pin-Priority: 900
EOF
    ui_ok "已配置 nginx.org stable 源（${EWO_OS_CODENAME}）"
    return 0
}

# 安装后验一下 nginx 是不是 nginx.org 那份（1.30+），不是就 fatal。
# 之所以放在 install_apt_packages 末尾而不是 nginx.sh：是要在 apt 流程
# 直接退出前发现问题，方便用户在排查阶段就能看到。
verify_nginx_version() {
    if [[ "${EWO_ALLOW_NGINX_OLD:-0}" == "1" ]]; then
        return 0
    fi
    if ! command -v nginx >/dev/null 2>&1; then
        ui_err "未找到 nginx 可执行文件，apt 安装可能没完成。"
        return 1
    fi
    local ver
    ver=$(nginx -v 2>&1 | sed -E 's/^nginx version: nginx\///; s/ .*$//')
    if [[ -z "${ver}" ]]; then
        ui_warn "无法解析 nginx 版本，跳过校验"
        return 0
    fi
    # 1.22/1.18/1.14 都是 Debian 自带版本（不同 Debian 版本），全部拒收
    if [[ "${ver}" =~ ^1\.(22|18|14|10|6|4)\. ]]; then
        ui_err "$(printf '装上的 nginx 是 %s（Debian 自带版本），不是预期的 nginx.org stable。\nnginx.org pin 可能没生效，请检查：\n  apt-cache policy nginx\n  cat /etc/apt/preferences.d/nginx-stable\n  cat /etc/apt/sources.list.d/nginx-stable.list\n' "$ver")"
        return 1
    fi
    ui_ok "nginx 版本：${ver}（来自 nginx.org）"
    return 0
}

install_apt_packages() {
    export DEBIAN_FRONTEND=noninteractive
    # Belt and braces: some packages still prompt at priority=high even with
    # frontend=noninteractive unless DEBCONF_NONINTERACTIVE_SEEN is set.
    export DEBCONF_NONINTERACTIVE_SEEN=true
    export APT_LISTCHANGES_FRONTEND=none

    # Pull nginx from nginx.org's stable channel — Debian 12 ships 1.22.1
    # which is below the CVE-2026-42945 fix boundary (1.30.1 / 1.31.0).
    if ! setup_nginx_org_repo; then
        ui_err "nginx.org 源配置失败，无法继续。"
        return 1
    fi

    ui_info "刷新 apt 软件源索引"
    run_stream apt-get update

    # Detect which PHP-FPM version is available in this Debian release.
    # Debian 12 ships 8.2; Debian 13 ships 8.3 or 8.4 depending on freeze date.
    local candidate=""
    for v in 8.4 8.3 8.2; do
        if apt-cache show "php${v}-fpm" >/dev/null 2>&1; then
            candidate="${v}"
            break
        fi
    done
    if [[ -z "${candidate}" ]]; then
        ui_err "未在此 Debian 版本中找到可用的 PHP-FPM（8.2/8.3/8.4）。"
        return 1
    fi
    EWO_PHP_VER="${candidate}"
    EWO_PHP_SOCK="/run/php/php${EWO_PHP_VER}-fpm-ewomail.sock"
    EWO_PHP_FPM_SERVICE="php${EWO_PHP_VER}-fpm"
    export EWO_PHP_VER EWO_PHP_SOCK EWO_PHP_FPM_SERVICE
    ui_ok "PHP-FPM 版本：${EWO_PHP_VER}"

    # Pre-seed postfix so dpkg does not prompt.
    debconf-set-selections <<EOF
postfix postfix/main_mailer_type select Internet Site
postfix postfix/mailname        string  ${EWO_DOMAIN}
postfix postfix/destinations    string  \$myhostname, localhost.\$mydomain, localhost
EOF

    ui_info "正在安装软件包（首次安装 5-10 分钟）"
    ui_dim "下面是 apt 实时输出，每行以 │ 开头。"

    local packages=(
        # The PHP admin panel shells out via \`sudo /ewomail/sbin/ewomail-helper\`;
        # sudo is NOT installed by default on Debian minimal images.
        sudo
        ca-certificates curl wget gnupg lsb-release unzip git
        rsync socat cron logrotate
        # Mail stack — DKIM signing is done by amavis, so opendkim is not
        # needed (its daemon would otherwise start with no usable config).
        postfix postfix-mysql postfix-policyd-spf-python
        dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd
        dovecot-mysql dovecot-sieve dovecot-managesieved
        amavisd-new spamassassin spamc clamav clamav-daemon clamav-freshclam
        # Web / DB / runtime
        mariadb-server mariadb-client
        nginx
        "php${EWO_PHP_VER}-fpm" "php${EWO_PHP_VER}-cli"
        "php${EWO_PHP_VER}-mysql" "php${EWO_PHP_VER}-mbstring"
        "php${EWO_PHP_VER}-xml"   "php${EWO_PHP_VER}-curl"
        "php${EWO_PHP_VER}-zip"   "php${EWO_PHP_VER}-gd"
        "php${EWO_PHP_VER}-intl"  "php${EWO_PHP_VER}-bcmath"
        "php${EWO_PHP_VER}-imap"  "php${EWO_PHP_VER}-opcache"
        # Security — python3-systemd is required for fail2ban's
        # `backend = systemd` jail config to read the journal.
        firewalld fail2ban python3-systemd
    )

    run_stream apt-get install -y --no-install-recommends "${packages[@]}"
    ui_ok "所有软件包已安装"

    if ! verify_nginx_version; then
        return 1
    fi

    # Stop services we will reconfigure; we start them again at the end.
    # SpamAssassin's systemd unit on Debian 12 is spamassassin.service (the
    # spamd name comes from the daemon binary, not the unit).
    # Use `systemctl cat` instead of parsing list-unit-files: the latter's
    # output format can include pager/color codes on some Debian images that
    # break our literal grep, leading to false negatives.
    for svc in postfix dovecot amavis spamassassin clamav-daemon clamav-freshclam nginx \
               "${EWO_PHP_FPM_SERVICE}" mariadb; do
        if systemctl cat "${svc}.service" >/dev/null 2>&1; then
            run_quiet systemctl stop "${svc}" || true
        fi
    done
}

enable_and_start_services() {
    # NOTE: spamassassin is intentionally NOT here. Debian 12's spamassassin
    # package no longer ships a daemon unit (only spamassassin-maintenance
    # for cron-like upkeep); spam scanning is performed in-process by amavis
    # via Mail::SpamAssassin Perl modules. Starting it would fail with
    # "Unit file not found".
    local services=(
        mariadb "${EWO_PHP_FPM_SERVICE}"
        postfix dovecot amavis
        clamav-daemon clamav-freshclam
        nginx firewalld fail2ban
    )
    for svc in "${services[@]}"; do
        if ! systemctl cat "${svc}.service" >/dev/null 2>&1; then
            ui_warn "未找到 service '${svc}.service'，已跳过。"
            continue
        fi
        run systemctl enable --now "${svc}"
    done

    # Verify each service actually reached 'active'. systemd's
    # ConditionPathExistsGlob (clamav-daemon waiting for daily.cvd) and
    # some postinst race conditions can leave a service enabled-but-inactive
    # even after `enable --now` returned 0. Retry once with explicit start.
    local failed=()
    for svc in "${services[@]}"; do
        systemctl cat "${svc}.service" >/dev/null 2>&1 || continue
        if [[ "$(systemctl is-active "${svc}" 2>/dev/null)" != "active" ]]; then
            ui_warn "${svc} 未运行，尝试再启一次……"
            run_quiet systemctl start "${svc}" || true
            sleep 1
            if [[ "$(systemctl is-active "${svc}" 2>/dev/null)" != "active" ]]; then
                failed+=("${svc}")
            fi
        fi
    done
    if [[ ${#failed[@]} -gt 0 ]]; then
        ui_warn "以下服务仍未启动：${failed[*]}"
        ui_warn "请逐个执行  ${UI_BOLD}journalctl -xeu <service>${UI_RESET}${UI_YELLOW} 排查后手动 systemctl start。"
    else
        ui_ok "所有服务已启动"
    fi
}
