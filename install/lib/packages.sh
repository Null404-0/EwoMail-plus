# Installs system packages from Debian repositories only.

setup_nginx_org_repo() {
    # Add nginx.org's stable APT repository and pin so that `nginx` resolves
    # to the upstream package, not Debian's 1.22.1.
    install -d -m 0755 /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/nginx.gpg ]]; then
        if ! curl -fsSL https://nginx.org/keys/nginx_signing.key 2>>"${LOG_FILE}" \
              | gpg --dearmor -o /etc/apt/keyrings/nginx.gpg 2>>"${LOG_FILE}"; then
            ui_warn "无法获取 nginx.org 签名密钥，回退到 Debian 自带 nginx（1.22）。"
            return 0
        fi
        chmod 0644 /etc/apt/keyrings/nginx.gpg
    fi
    cat > /etc/apt/sources.list.d/nginx-stable.list <<EOF
deb [signed-by=/etc/apt/keyrings/nginx.gpg] https://nginx.org/packages/debian ${EWO_OS_CODENAME} nginx
EOF
    # Pin so Debian's nginx never wins; nginx.org's package is always preferred.
    cat > /etc/apt/preferences.d/nginx-stable <<'EOF'
Package: nginx
Pin: origin nginx.org
Pin-Priority: 900
EOF
    ui_ok "已配置 nginx.org stable 源（${EWO_OS_CODENAME}）"
}

install_apt_packages() {
    export DEBIAN_FRONTEND=noninteractive
    # Belt and braces: some packages still prompt at priority=high even with
    # frontend=noninteractive unless DEBCONF_NONINTERACTIVE_SEEN is set.
    export DEBCONF_NONINTERACTIVE_SEEN=true
    export APT_LISTCHANGES_FRONTEND=none

    # Pull nginx from nginx.org's stable channel — Debian 12 ships 1.22.1
    # which is below the CVE-2026-42945 fix boundary (1.30.1 / 1.31.0).
    setup_nginx_org_repo

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

    # Stop services we will reconfigure; we start them again at the end.
    # Debian renamed SpamAssassin's unit to spamd.service (was spamassassin).
    # Use `systemctl cat` instead of parsing list-unit-files: the latter's
    # output format can include pager/color codes on some Debian images that
    # break our literal grep, leading to false negatives.
    for svc in postfix dovecot amavis spamd clamav-daemon clamav-freshclam nginx \
               "${EWO_PHP_FPM_SERVICE}" mariadb; do
        if systemctl cat "${svc}.service" >/dev/null 2>&1; then
            run_quiet systemctl stop "${svc}" || true
        fi
    done
}

enable_and_start_services() {
    local services=(
        mariadb "${EWO_PHP_FPM_SERVICE}"
        postfix dovecot amavis spamd
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
    ui_ok "所有服务已启动"
}
