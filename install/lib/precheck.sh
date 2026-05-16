# Pre-flight checks: OS, resources, DNS, clean machine.

precheck_os() {
    if [[ ! -f /etc/os-release ]]; then
        ui_err "/etc/os-release missing; cannot identify OS."
        exit 1
    fi
    # shellcheck disable=SC1091
    source /etc/os-release
    EWO_OS_ID="${ID:-unknown}"
    EWO_OS_VER="${VERSION_ID:-0}"
    EWO_OS_CODENAME="${VERSION_CODENAME:-}"
    export EWO_OS_ID EWO_OS_VER EWO_OS_CODENAME

    if [[ "${EWO_OS_ID}" != "debian" ]]; then
        ui_err "Unsupported OS: ${PRETTY_NAME:-${EWO_OS_ID}}. This installer only supports Debian 12/13."
        exit 1
    fi
    case "${EWO_OS_VER}" in
        12|13) ;;
        *)
            ui_err "Unsupported Debian version: ${EWO_OS_VER}. Need Debian 12 (bookworm) or 13 (trixie)."
            exit 1 ;;
    esac
    ui_ok "OS detected: Debian ${EWO_OS_VER} (${EWO_OS_CODENAME})"
}

precheck_clean_machine() {
    local conflicts=()
    for svc in mariadb mysql postfix dovecot nginx apache2 httpd; do
        if systemctl list-unit-files --type=service 2>/dev/null | grep -q "^${svc}\.service"; then
            if systemctl is-active --quiet "${svc}" 2>/dev/null; then
                conflicts+=("${svc} (active)")
            fi
        fi
    done
    if dpkg -l 2>/dev/null | grep -E '^ii\s+(mariadb-server|mysql-server|postfix|dovecot-core|nginx-(core|full|light)|apache2)\s' >/dev/null 2>&1; then
        conflicts+=("conflicting packages already installed")
    fi
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        ui_err "This VPS is not a clean install:"
        for c in "${conflicts[@]}"; do ui_err "  - ${c}"; done
        ui_err "EwoMail-plus requires a dedicated, clean machine. Reinstall the OS or use another VPS."
        exit 1
    fi
    ui_ok "Machine is clean (no conflicting services or packages)"
}

precheck_resources() {
    local mem_kb cpu_count disk_avail_g
    mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    cpu_count=$(nproc)
    disk_avail_g=$(df --output=avail -BG / | tail -1 | tr -dc '0-9')

    ui_info "Detected resources: ${cpu_count} CPU / $(( mem_kb / 1024 )) MB RAM / ${disk_avail_g} GB free on /"

    if (( mem_kb < 1900 * 1024 )); then
        ui_warn "Less than 2 GB RAM — Amavis + ClamAV may OOM. Consider adding swap or upgrading the plan."
    fi
    if (( disk_avail_g < 20 )); then
        ui_warn "Less than 20 GB free on /. Mail storage + ClamAV signatures need room."
    fi
}

prompt_domain() {
    while true; do
        prompt_default "Primary mail domain (e.g. example.com, NOT mail.example.com)" "" EWO_DOMAIN
        if [[ -z "${EWO_DOMAIN}" ]]; then
            ui_warn "Domain is required."
            continue
        fi
        if [[ ! "${EWO_DOMAIN}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$ ]]; then
            ui_warn "Looks invalid. Please use a bare domain like example.com."
            continue
        fi
        if [[ "${EWO_DOMAIN}" == mail.* ]]; then
            ui_warn "Don't include the 'mail.' prefix; the installer will create that A record requirement for you."
            continue
        fi
        break
    done
    EWO_MAIL_HOST="mail.${EWO_DOMAIN}"
    export EWO_DOMAIN EWO_MAIL_HOST
    ui_ok "Using domain: ${EWO_DOMAIN} (mail host: ${EWO_MAIL_HOST})"
}

prompt_admin_email() {
    local default_email="admin@${EWO_DOMAIN}"
    while true; do
        prompt_default "Admin contact email (for Let's Encrypt notifications)" "${default_email}" EWO_ADMIN_EMAIL
        # Conservative check: keep characters that are SQL-safe to interpolate
        # later (we use heredoc SQL in admin_init.sh).
        if [[ "${EWO_ADMIN_EMAIL}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            break
        fi
        ui_warn "That doesn't look like a valid email address. Please try again."
    done
    export EWO_ADMIN_EMAIL
}

prompt_db_admin_enabled() {
    prompt_yesno "Expose Adminer (database admin) on a random path? You can toggle this in the panel later." "no" EWO_DB_ADMIN_ENABLED
    export EWO_DB_ADMIN_ENABLED
}

prompt_request_letsencrypt() {
    prompt_yesno "Try to issue a Let's Encrypt certificate at the end? (DNS must already point here)" "yes" EWO_LE_REQUEST
    export EWO_LE_REQUEST
}

precheck_dns() {
    local domain="$1"
    ui_info "Checking DNS records …"
    local public_ip
    public_ip=$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)
    if [[ -z "${public_ip}" ]]; then
        public_ip=$(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || true)
    fi
    if [[ -z "${public_ip}" ]]; then
        ui_warn "Could not auto-detect public IPv4. DNS verification will be skipped."
        return 0
    fi
    export EWO_PUBLIC_IP="${public_ip}"
    ui_ok "Public IPv4 detected: ${public_ip}"

    local a_record
    a_record=$(getent ahostsv4 "mail.${domain}" 2>/dev/null | awk '{print $1}' | head -1 || true)
    if [[ "${a_record}" == "${public_ip}" ]]; then
        ui_ok "mail.${domain} → ${a_record}  (matches this VPS)"
    elif [[ -n "${a_record}" ]]; then
        ui_warn "mail.${domain} resolves to ${a_record}, but this VPS is ${public_ip}."
        ui_warn "Update your DNS to add  ${UI_BOLD}A  mail   ${public_ip}${UI_RESET}  on ${domain}, then re-run."
        prompt_yesno "Continue anyway? (the installer will still work, but mail will not flow until DNS catches up)" "no" cont
        [[ "${cont}" != "yes" ]] && { ui_err "Aborted."; exit 1; }
    else
        ui_warn "mail.${domain} has no A record yet."
        cat <<EOF
${UI_BOLD}Required DNS records on ${domain}${UI_RESET} (the installer will print final values at the end):
  ${UI_CYAN}A      mail        ${public_ip}${UI_RESET}
  ${UI_CYAN}MX     @           mail.${domain}.  (priority 10)${UI_RESET}
  ${UI_CYAN}TXT    @           "v=spf1 mx ~all"${UI_RESET}
  ${UI_CYAN}TXT    _dmarc      "v=DMARC1; p=quarantine; rua=mailto:postmaster@${domain}"${UI_RESET}
  ${UI_CYAN}TXT    dkim._domainkey  (value printed after install)${UI_RESET}
Reverse DNS (PTR) on ${public_ip} should point to mail.${domain}; ask your VPS provider.
EOF
        prompt_yesno "Continue anyway? You can add DNS later, mail won't flow until then." "yes" cont
        [[ "${cont}" != "yes" ]] && { ui_err "Aborted."; exit 1; }
    fi
}
