#!/usr/bin/env bash
# EwoMail-plus interactive installer
# Target OS: Debian 12 / Debian 13 (clean install, dedicated VPS).

set -Eeuo pipefail

INSTALLER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${INSTALLER_DIR}/.." && pwd)"
EWOMAIL_PREFIX="/ewomail"
STATE_DIR="${EWOMAIL_PREFIX}/.state"
CREDENTIALS_FILE="${EWOMAIL_PREFIX}/credentials.txt"
LOG_FILE="/var/log/ewomail-install.log"

export INSTALLER_DIR REPO_DIR EWOMAIL_PREFIX STATE_DIR CREDENTIALS_FILE LOG_FILE

# Shared libraries.
# shellcheck source=lib/ui.sh
source "${INSTALLER_DIR}/lib/ui.sh"
# shellcheck source=lib/precheck.sh
source "${INSTALLER_DIR}/lib/precheck.sh"
# shellcheck source=lib/credentials.sh
source "${INSTALLER_DIR}/lib/credentials.sh"
# shellcheck source=lib/packages.sh
source "${INSTALLER_DIR}/lib/packages.sh"
# shellcheck source=lib/mariadb.sh
source "${INSTALLER_DIR}/lib/mariadb.sh"
# shellcheck source=lib/postfix.sh
source "${INSTALLER_DIR}/lib/postfix.sh"
# shellcheck source=lib/dovecot.sh
source "${INSTALLER_DIR}/lib/dovecot.sh"
# shellcheck source=lib/amavis.sh
source "${INSTALLER_DIR}/lib/amavis.sh"
# shellcheck source=lib/php.sh
source "${INSTALLER_DIR}/lib/php.sh"
# shellcheck source=lib/nginx.sh
source "${INSTALLER_DIR}/lib/nginx.sh"
# shellcheck source=lib/firewall.sh
source "${INSTALLER_DIR}/lib/firewall.sh"
# shellcheck source=lib/ssl.sh
source "${INSTALLER_DIR}/lib/ssl.sh"
# shellcheck source=lib/webapps.sh
source "${INSTALLER_DIR}/lib/webapps.sh"
# shellcheck source=lib/admin_init.sh
source "${INSTALLER_DIR}/lib/admin_init.sh"
# shellcheck source=lib/fail2ban.sh
source "${INSTALLER_DIR}/lib/fail2ban.sh"
# shellcheck source=lib/summary.sh
source "${INSTALLER_DIR}/lib/summary.sh"

main() {
    require_root
    init_logging
    trap on_error ERR

    ui_banner "EwoMail-plus 安装程序"

    precheck_os
    precheck_clean_machine
    precheck_resources

    prompt_domain
    prompt_admin_email
    prompt_db_admin_enabled
    prompt_request_letsencrypt
    prompt_swap

    precheck_dns "${EWO_DOMAIN}"
    confirm_proceed

    generate_credentials

    step "安装系统软件包（Debian apt + nginx.org stable）"
    install_apt_packages

    step "配置 MariaDB"
    setup_mariadb

    step "配置 Postfix"
    setup_postfix

    step "配置 Dovecot"
    setup_dovecot

    step "配置 Amavis + ClamAV + SpamAssassin + DKIM"
    setup_amavis

    step "配置 PHP-FPM"
    setup_php_fpm

    step "安装 Web 应用（管理后台 / SnappyMail / Adminer）"
    install_webapps

    step "配置 Nginx"
    setup_nginx

    step "初始化业务数据库与管理员账号"
    init_application_db

    step "配置 fail2ban"
    setup_fail2ban

    step "配置 firewalld 防火墙"
    setup_firewall

    step "安装 acme.sh 并申请 Let's Encrypt 证书"
    setup_ssl

    step "启动所有服务"
    enable_and_start_services

    step "写入凭据文件"
    write_credentials_file

    print_summary

    ui_ok "全部完成。"
}

main "$@"
