# Installs system packages from Debian repositories only.

install_apt_packages() {
    export DEBIAN_FRONTEND=noninteractive
    case "${EWO_OS_VER}" in
        12) EWO_PHP_VER="8.2" ;;
        13) EWO_PHP_VER="8.4" ;;
        *)  ui_err "Unhandled Debian version ${EWO_OS_VER}"; return 1 ;;
    esac
    export EWO_PHP_VER
    EWO_PHP_SOCK="/run/php/php${EWO_PHP_VER}-fpm-ewomail.sock"
    EWO_PHP_FPM_SERVICE="php${EWO_PHP_VER}-fpm"
    export EWO_PHP_SOCK EWO_PHP_FPM_SERVICE

    ui_info "Refreshing package index"
    run apt-get update

    # Pre-seed postfix so dpkg does not prompt.
    debconf-set-selections <<EOF
postfix postfix/main_mailer_type select Internet Site
postfix postfix/mailname        string  ${EWO_DOMAIN}
postfix postfix/destinations    string  \$myhostname, localhost.\$mydomain, localhost
EOF

    ui_info "Installing packages (this can take 5-10 minutes)"

    local packages=(
        ca-certificates curl wget gnupg lsb-release unzip git
        rsync socat cron logrotate
        # Mail stack
        postfix postfix-mysql
        dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd
        dovecot-mysql dovecot-sieve dovecot-managesieved
        amavisd-new spamassassin clamav clamav-daemon clamav-freshclam
        opendkim opendkim-tools
        # Web / DB / runtime
        mariadb-server mariadb-client
        nginx
        "php${EWO_PHP_VER}-fpm" "php${EWO_PHP_VER}-cli"
        "php${EWO_PHP_VER}-mysql" "php${EWO_PHP_VER}-mbstring"
        "php${EWO_PHP_VER}-xml"   "php${EWO_PHP_VER}-curl"
        "php${EWO_PHP_VER}-zip"   "php${EWO_PHP_VER}-gd"
        "php${EWO_PHP_VER}-intl"  "php${EWO_PHP_VER}-bcmath"
        "php${EWO_PHP_VER}-imap"  "php${EWO_PHP_VER}-opcache"
        # Security
        firewalld fail2ban
    )

    run apt-get install -y --no-install-recommends "${packages[@]}"
    ui_ok "All packages installed"

    # Stop services we will reconfigure; we start them again at the end.
    for svc in postfix dovecot amavis spamassassin clamav-daemon clamav-freshclam nginx \
               "${EWO_PHP_FPM_SERVICE}" mariadb opendkim; do
        if systemctl list-unit-files --type=service | grep -q "^${svc}\.service"; then
            run_quiet systemctl stop "${svc}" || true
        fi
    done
}

enable_and_start_services() {
    local services=(
        mariadb "${EWO_PHP_FPM_SERVICE}"
        postfix dovecot amavis spamassassin
        clamav-daemon clamav-freshclam
        nginx firewalld fail2ban
    )
    for svc in "${services[@]}"; do
        run systemctl enable --now "${svc}"
    done
    ui_ok "All services enabled & running"
}
