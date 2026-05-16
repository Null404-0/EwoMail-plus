# Installs system packages from Debian repositories only.

install_apt_packages() {
    export DEBIAN_FRONTEND=noninteractive
    # Belt and braces: some packages still prompt at priority=high even with
    # frontend=noninteractive unless DEBCONF_NONINTERACTIVE_SEEN is set.
    export DEBCONF_NONINTERACTIVE_SEEN=true
    export APT_LISTCHANGES_FRONTEND=none

    ui_info "Refreshing package index"
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
        ui_err "No supported PHP-FPM package (8.2/8.3/8.4) found in this Debian release."
        return 1
    fi
    EWO_PHP_VER="${candidate}"
    EWO_PHP_SOCK="/run/php/php${EWO_PHP_VER}-fpm-ewomail.sock"
    EWO_PHP_FPM_SERVICE="php${EWO_PHP_VER}-fpm"
    export EWO_PHP_VER EWO_PHP_SOCK EWO_PHP_FPM_SERVICE
    ui_ok "PHP-FPM version: ${EWO_PHP_VER}"

    # Pre-seed postfix so dpkg does not prompt.
    debconf-set-selections <<EOF
postfix postfix/main_mailer_type select Internet Site
postfix postfix/mailname        string  ${EWO_DOMAIN}
postfix postfix/destinations    string  \$myhostname, localhost.\$mydomain, localhost
EOF

    ui_info "Installing packages (this can take 5-10 minutes on a fresh VPS)"
    ui_dim "Live apt output follows; each line is prefixed with │."

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
    ui_ok "All packages installed"

    # Stop services we will reconfigure; we start them again at the end.
    # Debian renamed SpamAssassin's unit to spamd.service (was spamassassin).
    for svc in postfix dovecot amavis spamd clamav-daemon clamav-freshclam nginx \
               "${EWO_PHP_FPM_SERVICE}" mariadb; do
        if systemctl list-unit-files --type=service | grep -q "^${svc}\.service"; then
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
        # Skip cleanly if the unit doesn't exist on this distro (e.g. an old
        # spamassassin layout). Required ones (mariadb, postfix, dovecot,
        # nginx, php-fpm) will always be present so a missing unit there
        # would still surface as a hard error via the next service that
        # depends on it.
        if ! systemctl list-unit-files --type=service | grep -q "^${svc}\.service"; then
            ui_warn "Service unit '${svc}.service' not found; skipping."
            continue
        fi
        run systemctl enable --now "${svc}"
    done
    ui_ok "All services enabled & running"
}
