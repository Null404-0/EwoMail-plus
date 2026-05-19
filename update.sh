#!/usr/bin/env bash
# EwoMail-plus updater
# Pulls latest from origin/master, syncs the admin code to /ewomail/www/,
# re-renders service configs and the privilege helper, applies any
# idempotent DB additions, and reloads affected services.
#
# Safe to re-run. Preserves user data (mailboxes, attachments, sessions,
# Smarty compiled cache), random URL paths, admin password and code_key.
#
# Usage:
#   bash update.sh                    # full update
#   bash update.sh --code-only        # skip service-config re-render
#   bash update.sh --no-git-pull      # use whatever's already checked out

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="${REPO_DIR}/install"
EWOMAIL_PREFIX="/ewomail"
CREDENTIALS_FILE="${EWOMAIL_PREFIX}/credentials.txt"
LOG_FILE="/var/log/ewomail-update.log"
BACKUP_DIR="${EWOMAIL_PREFIX}/.update-backup/$(date +%Y%m%d-%H%M%S)"

CODE_ONLY=0
DO_GIT_PULL=1
for arg in "$@"; do
    case "$arg" in
        --code-only)   CODE_ONLY=1 ;;
        --no-git-pull) DO_GIT_PULL=0 ;;
        -h|--help)
            sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "未知参数：$arg"; exit 2 ;;
    esac
done

export INSTALLER_DIR REPO_DIR EWOMAIL_PREFIX CREDENTIALS_FILE LOG_FILE

# shellcheck source=install/lib/ui.sh
source "${INSTALLER_DIR}/lib/ui.sh"
# shellcheck source=install/lib/credentials.sh
source "${INSTALLER_DIR}/lib/credentials.sh"

# Update has 6 phases — override the installer's default total so [N/14] is sane.
UI_STEP_TOTAL=6

require_root
init_logging
trap on_error ERR

ui_banner "EwoMail-plus 更新程序"

# 先把要做的事说清楚，让用户有机会按 Ctrl-C 退出。
cat <<EOF
本次将执行以下操作：
  1. git fetch origin master && fast-forward
  2. 备份当前 /etc/{nginx,postfix,dovecot,amavis,fail2ban} 关键配置
  3. 同步 ewomail-admin 代码到 /ewomail/www/ewomail-admin
     （保留 cache/upload/attachment/session 用户数据）
  4. 重新渲染服务配置 + 权限助手（除非加了 --code-only）
  5. 应用 DB 增量（CREATE/INSERT IGNORE，从不删除已有数据）
  6. reload nginx / postfix / dovecot / amavis / fail2ban / php-fpm

不会做：apt 安装、修改 MariaDB root 密码、重新签发证书、改 admin 密码、动 URL 随机路径。
中断不会导致数据损坏；如果配置渲染失败 nginx -t 会自动回滚 vhost。

EOF
printf '%s继续？[y/N]：%s ' "${UI_BOLD}" "${UI_RESET}"
read -r ans
case "${ans,,}" in
    y|yes) ;;
    *) ui_err "用户取消。"; exit 1 ;;
esac

# ---- 预检 ---------------------------------------------------------------
[[ -f "${CREDENTIALS_FILE}" ]] || {
    ui_err "${CREDENTIALS_FILE} 不存在——本机似乎从未通过 install.sh 部署过。"
    ui_err "首次部署请运行：./install/install.sh"
    exit 1
}
[[ -d /ewomail/www/ewomail-admin ]] || {
    ui_err "/ewomail/www/ewomail-admin 不存在——部署不完整？"
    exit 1
}
[[ -d "${REPO_DIR}/.git" ]] || {
    ui_err "${REPO_DIR} 不是 git 仓库；无法 git pull。"
    exit 1
}

# 从 /etc/os-release 取版本（renderer 用得到）
# shellcheck disable=SC1091
source /etc/os-release
export EWO_OS_VER="${VERSION_ID:-0}"
export EWO_OS_CODENAME="${VERSION_CODENAME:-}"

# 从凭据文件提取键值。Summary 写入格式：
#   keyname<spaces>= value
# 用默认 FS（空白）切，$1=key、$2='='、$3+=value（带空格的密码也能正确拼回）。
_cred_get() {
    awk -v k="$1" '$1 == k && $2 == "=" {
        out = $3
        for (i = 4; i <= NF; i++) out = out " " $i
        print out; exit
    }' "${CREDENTIALS_FILE}"
}
export EWO_DOMAIN="$(_cred_get domain)"
export EWO_MAIL_HOST="$(_cred_get mail_host)"
export EWO_PUBLIC_IP="$(_cred_get public_ip)"
export EWO_MYSQL_ROOT_PWD="$(_cred_get root_password)"
export EWO_MYSQL_EWOMAIL_PWD="$(_cred_get ewomail_db_password)"
export EWO_ADMIN_PWD="$(_cred_get password)"

[[ -n "${EWO_DOMAIN}" && -n "${EWO_MYSQL_EWOMAIL_PWD}" ]] || {
    ui_err "无法从 ${CREDENTIALS_FILE} 解析出 domain / 密码——文件可能被手动改过。"
    exit 1
}

# 从数据库读 随机 URL 路径 / DB 开关 / LE 邮箱
_db_get() { mysql -uroot -N -B ewomail -e "SELECT value FROM i_panel_setting WHERE name='$1'" 2>/dev/null; }
export EWO_ADMIN_PATH="$(_db_get admin_path)"
export EWO_DB_PATH="$(_db_get db_path)"
export EWO_DB_ADMIN_ENABLED="$(_db_get db_admin_enable)"
export EWO_ADMIN_EMAIL="$(_db_get le_email)"
[[ -z "${EWO_ADMIN_EMAIL}" ]] && EWO_ADMIN_EMAIL="admin@${EWO_DOMAIN}"
[[ -z "${EWO_ADMIN_PATH}" || -z "${EWO_DB_PATH}" ]] && {
    ui_err "从 i_panel_setting 读不到 admin_path / db_path；DB 是否可达？"
    exit 1
}

# code_key 不应该更换（更换会让所有已登录 session 失效）。从现有 config.php 提取保留。
export EWO_CODE_KEY="$(awk -F"'" "/'code_key'/{print \$4; exit}" /ewomail/www/ewomail-admin/core/config.php 2>/dev/null)"
[[ -z "${EWO_CODE_KEY}" ]] && EWO_CODE_KEY="$(_random_password 32 2>/dev/null || head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c32)"

# 探测 PHP 版本（renderer 用得到）
EWO_PHP_VER="$(php -v 2>/dev/null | awk 'NR==1{split($2,a,"."); print a[1]"."a[2]}')"
[[ -z "${EWO_PHP_VER}" ]] && EWO_PHP_VER="8.2"
export EWO_PHP_VER
export EWO_PHP_SOCK="/run/php/php${EWO_PHP_VER}-fpm-ewomail.sock"
export EWO_PHP_FPM_SERVICE="php${EWO_PHP_VER}-fpm"

ui_info "域名：${EWO_DOMAIN}  邮件主机：${EWO_MAIL_HOST}"
ui_info "PHP-FPM：${EWO_PHP_VER}   后台路径：/${EWO_ADMIN_PATH}/   DB 入口：/${EWO_DB_PATH}/ (启用=${EWO_DB_ADMIN_ENABLED})"

# ---- 1. 拉取最新代码 -----------------------------------------------------
step "拉取最新代码"
if (( DO_GIT_PULL )); then
    cd "${REPO_DIR}"
    local_before="$(git rev-parse HEAD)"
    run git fetch origin master
    if ! git merge --ff-only origin/master >>"${LOG_FILE}" 2>&1; then
        ui_err "本地分支与 origin/master 有冲突，无法 fast-forward。"
        ui_err "请先用  git status / git log  查看，并手动 reset/merge 后再运行。"
        exit 1
    fi
    local_after="$(git rev-parse HEAD)"
    if [[ "${local_before}" == "${local_after}" ]]; then
        ui_ok "已是最新版本，无新提交"
    else
        ui_ok "已更新到 $(git log --oneline -1)"
        ui_dim "新提交："
        git log --oneline "${local_before}..${local_after}" | sed 's/^/    /'
    fi
else
    ui_info "已跳过 git pull（--no-git-pull）"
fi

# ---- 2. 备份关键文件（出错时可手动还原） --------------------------------
step "备份当前配置到 ${BACKUP_DIR}"
install -d -m 0700 "${BACKUP_DIR}"
for f in /etc/nginx/sites-available/ewomail.conf /etc/postfix/main.cf /etc/postfix/master.cf \
         /etc/dovecot/dovecot.conf /etc/amavis/conf.d/50-user \
         /etc/php/${EWO_PHP_VER}/fpm/pool.d/ewomail.conf \
         /ewomail/www/ewomail-admin/core/config.php \
         /ewomail/sbin/ewomail-helper /etc/fail2ban/jail.local; do
    [[ -f "$f" ]] && cp --parents "$f" "${BACKUP_DIR}/" 2>/dev/null || true
done
ui_ok "备份完成"

# ---- 3. 同步 admin 代码 --------------------------------------------------
step "同步 admin 代码到 /ewomail/www/ewomail-admin"
# --delete 让仓库里删除的文件也同步删除；--exclude 保留用户数据。
run rsync -a --delete \
    --exclude='cache/' \
    --exclude='upload/' \
    --exclude='attachment/' \
    --exclude='session/' \
    "${REPO_DIR}/ewomail-admin/" /ewomail/www/ewomail-admin/

# 重新渲染 core/config.php（覆盖 rsync 拷过来的占位版）
render_template "${INSTALLER_DIR}/templates/snappymail/admin-config.php" \
                /ewomail/www/ewomail-admin/core/config.php
chmod 0440 /ewomail/www/ewomail-admin/core/config.php
chown www-data:www-data /ewomail/www/ewomail-admin/core/config.php

# 清掉 Smarty 编译缓存，避免旧 .php 编译产物挡道
if [[ -d /ewomail/www/ewomail-admin/cache/templates ]]; then
    find /ewomail/www/ewomail-admin/cache/templates -mindepth 1 -delete 2>/dev/null || true
fi

# 修一遍权限：rsync 复制走的权限来自仓库（一般 0644/0755），但 session 目录需要 0770
chown -R www-data:www-data /ewomail/www/ewomail-admin
chmod 0770 /ewomail/www/session /ewomail/www/session/* 2>/dev/null || true
ui_ok "admin 代码已同步并清缓存"

# ---- 4. 服务配置 re-render（可 --code-only 跳过） -------------------------
if (( CODE_ONLY )); then
    ui_info "已跳过服务配置 re-render（--code-only）"
else
    step "重新渲染服务配置"

    # Postfix
    render_template "${INSTALLER_DIR}/templates/postfix/main.cf"   /etc/postfix/main.cf
    render_template "${INSTALLER_DIR}/templates/postfix/master.cf" /etc/postfix/master.cf
    for f in mysql-mailbox-domains.cf mysql-mailbox-maps.cf mysql-alias-maps.cf \
             mysql-sender-login-maps.cf mysql_bcc_user.cf; do
        render_template "${INSTALLER_DIR}/templates/postfix/mysql/${f}" "/etc/postfix/mysql/${f}"
        chown root:postfix "/etc/postfix/mysql/${f}"
        chmod 0640 "/etc/postfix/mysql/${f}"
    done

    # Dovecot
    render_template "${INSTALLER_DIR}/templates/dovecot/dovecot.conf"         /etc/dovecot/dovecot.conf
    render_template "${INSTALLER_DIR}/templates/dovecot/dovecot-sql.conf.ext" /etc/dovecot/dovecot-sql.conf.ext
    chgrp dovecot /etc/dovecot/dovecot-sql.conf.ext
    chmod 0640    /etc/dovecot/dovecot-sql.conf.ext
    for f in 10-auth.conf 10-logging.conf 10-mail.conf 10-master.conf 10-ssl.conf \
             15-lda.conf 15-mailboxes.conf 20-imap.conf 20-pop3.conf 20-lmtp.conf \
             20-managesieve.conf 90-sieve.conf 90-quota.conf auth-sql.conf.ext; do
        render_template "${INSTALLER_DIR}/templates/dovecot/conf.d/${f}" "/etc/dovecot/conf.d/${f}"
    done

    # Amavis (50-user is rendered; DKIM key NOT regenerated)
    render_template "${INSTALLER_DIR}/templates/amavis/50-user" /etc/amavis/conf.d/50-user

    # PHP-FPM pool
    render_template "${INSTALLER_DIR}/templates/php-fpm/ewomail.conf" \
                    "/etc/php/${EWO_PHP_VER}/fpm/pool.d/ewomail.conf"

    # fail2ban
    render_template "${INSTALLER_DIR}/templates/fail2ban/jail.local"           /etc/fail2ban/jail.local
    render_template "${INSTALLER_DIR}/templates/fail2ban/postfix-ewomail.conf" /etc/fail2ban/filter.d/postfix-ewomail.conf

    # Nginx snippets + vhost。Vhost 渲染后要按当前 DB 状态再决定 Adminer 是否封禁。
    render_template "${INSTALLER_DIR}/templates/nginx/nginx.conf"             /etc/nginx/nginx.conf
    render_template "${INSTALLER_DIR}/templates/nginx/snippets/php.conf"      /etc/nginx/snippets/ewomail-php.conf
    render_template "${INSTALLER_DIR}/templates/nginx/snippets/security.conf" /etc/nginx/snippets/ewomail-security.conf
    render_template "${INSTALLER_DIR}/templates/nginx/snippets/ssl.conf"      /etc/nginx/snippets/ewomail-ssl.conf
    render_template "${INSTALLER_DIR}/templates/nginx/ewomail.conf"           /etc/nginx/sites-available/ewomail.conf
    rm -f /etc/nginx/conf.d/default.conf  # nginx.org 包带的默认 vhost
    if [[ "${EWO_DB_ADMIN_ENABLED}" == "yes" ]]; then
        sed -i '/## EWOMAIL_DB_ENABLED ##/d' /etc/nginx/sites-available/ewomail.conf
    else
        sed -i 's|## EWOMAIL_DB_ENABLED ##|return 404; # EWOMAIL_DB_DISABLED|' /etc/nginx/sites-available/ewomail.conf
    fi
    ln -sf /etc/nginx/sites-available/ewomail.conf /etc/nginx/sites-enabled/ewomail.conf

    # 验证 nginx；失败则回滚 vhost
    if ! nginx -t >>"${LOG_FILE}" 2>&1; then
        ui_err "nginx -t 失败，已回滚 vhost。请查看 ${LOG_FILE} 排错。"
        cp "${BACKUP_DIR}/etc/nginx/sites-available/ewomail.conf" /etc/nginx/sites-available/ewomail.conf 2>/dev/null || true
        exit 1
    fi
    ui_ok "服务配置已 re-render（nginx -t 通过）"

    # 权限助手脚本
    install -d -m 0750 -o root -g www-data /ewomail/sbin
    render_template "${INSTALLER_DIR}/templates/admin-helper/ewomail-helper" /ewomail/sbin/ewomail-helper
    chmod 0750 /ewomail/sbin/ewomail-helper
    chown root:www-data /ewomail/sbin/ewomail-helper

    # sudoers fragment（idempotent，每次覆盖确保规则一致）
    install -d -m 0750 -o root -g root /etc/sudoers.d
    cat > /etc/sudoers.d/ewomail <<EOF
www-data ALL=(root) NOPASSWD: /ewomail/sbin/ewomail-helper
Defaults!/ewomail/sbin/ewomail-helper !requiretty
EOF
    chmod 0440 /etc/sudoers.d/ewomail
    run visudo -cf /etc/sudoers.d/ewomail
    ui_ok "权限助手已更新"
fi

# ---- 5. DB 增量（幂等） ---------------------------------------------------
step "应用 DB 增量（idempotent）"
mysql -uroot ewomail <<'EOF' 2>>"${LOG_FILE}"
CREATE TABLE IF NOT EXISTS i_panel_setting (
    name  VARCHAR(64) PRIMARY KEY,
    value TEXT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 原 EwoMail install.sql 漏建 i_day_record（老版本是某个独立组件首次写入
-- 时才隐式建表），PHP 直接 SELECT/UPDATE 这张表，缺了会 500。
-- 现存安装跑到这里时如果已有该表（数据完好）就跳过。
CREATE TABLE IF NOT EXISTS i_day_record (
    day_id INT NOT NULL AUTO_INCREMENT,
    email  VARCHAR(100) NOT NULL,
    day    DATE NOT NULL,
    s_num  INT NOT NULL DEFAULT 0 COMMENT '当日发送数',
    c_num  INT NOT NULL DEFAULT 0 COMMENT '当日接收数',
    PRIMARY KEY (day_id),
    UNIQUE KEY uniq_email_day (email, day),
    KEY idx_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='每日收发统计';

INSERT IGNORE INTO i_admin_menu (menu_id, mark, lang, url, top_id, edit, del, edit_id, sort) VALUES
  (106, '数据导入/导出','数据导入/导出','/DataPort', 100, 0, 0, 0, 10),
  (207, 'Webmail 品牌','Webmail 品牌','/System/webmail-config', 200, 1, 0, 0, 40),
  (300, '服务器',  '服务器',   '',          0,   0, 0, 0, 50),
  (301, '防火墙',  '防火墙',   '/Firewall', 300, 1, 1, 0, 51),
  (302, 'Nginx',  'Nginx',     '/Nginx',    300, 1, 0, 0, 52),
  (303, 'SSL证书','SSL证书',   '/Cert',     300, 1, 0, 0, 53),
  (304, '面板设置','面板设置', '/Setting',  300, 1, 0, 0, 54);
-- Also normalise rows from earlier installs that still have English values.
UPDATE i_admin_menu SET mark='服务器',   lang='服务器'    WHERE menu_id=300 AND lang IN ('Server','服务器');
UPDATE i_admin_menu SET mark='防火墙',   lang='防火墙'    WHERE menu_id=301 AND lang IN ('Firewall','防火墙');
UPDATE i_admin_menu SET mark='Nginx',    lang='Nginx'     WHERE menu_id=302;
UPDATE i_admin_menu SET mark='SSL证书',  lang='SSL证书'   WHERE menu_id=303 AND lang IN ('SSL','SSL证书');
UPDATE i_admin_menu SET mark='面板设置', lang='面板设置'  WHERE menu_id=304 AND lang IN ('Settings','面板设置');
EOF
ui_ok "DB 增量已应用"

# ---- 6. Reload 服务 -------------------------------------------------------
if (( CODE_ONLY )); then
    # Only PHP-FPM cares about admin code (opcache invalidation).
    step "重启 PHP-FPM（让 opcache 重新加载 admin 代码）"
    run systemctl restart "${EWO_PHP_FPM_SERVICE}"
else
    step "Reload 受影响的服务"
    for svc in "${EWO_PHP_FPM_SERVICE}" nginx postfix dovecot amavis fail2ban; do
        if systemctl is-active --quiet "${svc}"; then
            run_quiet systemctl reload-or-restart "${svc}" || run_quiet systemctl restart "${svc}" || true
        fi
    done
    ui_ok "服务已 reload"
fi

# ---- 7. SnappyMail UNICODE plugin sync ----------------------------------
# 把 repo 里的 plugin 推到 SnappyMail data 目录，重新启用，并刷一遍配置
# （保留 DB 里已存的 turnstile/outbound 值）。SnappyMail 没装时跳过。
if [[ -d /ewomail/www/snappymail && -d "${REPO_DIR}/snappymail-plugin/unicode" ]]; then
    step "同步 UNICODE plugin 到 SnappyMail"
    plugin_dst=/ewomail/www/snappymail/data/_data_/_default_/plugins/unicode
    install -d -m 0750 -o www-data -g www-data \
        /ewomail/www/snappymail/data/_data_/_default_/plugins
    rm -rf "${plugin_dst}"
    cp -a "${REPO_DIR}/snappymail-plugin/unicode" "${plugin_dst}"
    chown -R root:www-data "${plugin_dst}"
    find "${plugin_dst}" -type d -exec chmod 0750 {} +
    find "${plugin_dst}" -type f -exec chmod 0640 {} +
    if [[ -d "${plugin_dst}/assets" ]]; then
        chmod 0755 "${plugin_dst}/assets"
        find "${plugin_dst}/assets" -type f -exec chmod 0644 {} +
    fi

    /ewomail/sbin/ewomail-helper snappy-plugin-enable unicode \
        >>"${LOG_FILE}" 2>&1 || ui_warn "snappy-plugin-enable 失败（详见日志）"

    # 从 DB 读现有 turnstile 配置，重新推到 plugin（覆盖 cp 进来的占位 config.json）
    cur_enabled=$(mysql -uroot -N -B ewomail -e "SELECT value FROM i_panel_setting WHERE name='turnstile_enabled'" 2>/dev/null || echo "no")
    cur_site=$(mysql -uroot -N -B ewomail -e "SELECT value FROM i_panel_setting WHERE name='turnstile_site_key'" 2>/dev/null || echo "")
    cur_secret=$(mysql -uroot -N -B ewomail -e "SELECT value FROM i_panel_setting WHERE name='turnstile_secret_key'" 2>/dev/null || echo "")
    cur_outbound=$(mysql -uroot -N -B ewomail -e "SELECT value FROM i_panel_setting WHERE name='outbound_disabled'" 2>/dev/null || echo "no")

    # 用 PHP 拼合法 JSON 防字段里有特殊字符
    payload=$(php -r '
        echo json_encode([
            "turnstile_enabled"    => getenv("E") ?: "no",
            "turnstile_site_key"   => getenv("S") ?: "",
            "turnstile_secret_key" => getenv("K") ?: "",
            "outbound_disabled"    => getenv("O") ?: "no",
        ], JSON_UNESCAPED_UNICODE);
    ' E="${cur_enabled:-no}" S="${cur_site}" K="${cur_secret}" O="${cur_outbound:-no}")

    printf '%s' "${payload}" | /ewomail/sbin/ewomail-helper snappy-plugin-config-write unicode \
        >>"${LOG_FILE}" 2>&1 || ui_warn "snappy-plugin-config-write 失败（详见日志）"

    # 默认主题（仅当当前是 Default 时改成 Black Wood，已自定义则跳过）
    /ewomail/sbin/ewomail-helper snappy-set-theme "Black Wood" \
        >>"${LOG_FILE}" 2>&1 || ui_warn "snappy-set-theme 失败（详见日志）"

    # 强制刷新 SnappyMail 的 plugin asset 缓存 ——
    # SnappyMail 把所有 enabled plugin 的 CSS/JS 合并打包成一个带 hash 的 URL
    # 提供给浏览器。打包的 hash 基于源文件 mtime，git checkout 出来的文件
    # mtime 是 clone 当时的，cp -a 又保留 mtime，所以 update 完 plugin 文件
    # mtime 可能比 SnappyMail 缓存目录里那份还旧 → SnappyMail 以为没变化 →
    # 继续给浏览器发旧 bundle。touch 一下强制比缓存新。
    find "${plugin_dst}" -exec touch {} + 2>/dev/null || true
    rm -rf /ewomail/www/snappymail/data/_data_/_default_/cache 2>/dev/null || true

    ui_ok "UNICODE plugin 已同步（缓存已刷新）"
fi

# ---- 8. 总结 -------------------------------------------------------------
echo
ui_ok "更新完成。"
ui_info "如发现问题，本次操作前的配置备份在 ${BACKUP_DIR}"
ui_info "回滚单文件：cp ${BACKUP_DIR}/<path> <path>  然后  systemctl reload <svc>"
