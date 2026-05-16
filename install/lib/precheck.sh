# Pre-flight checks: OS, resources, DNS, clean machine.

precheck_os() {
    if [[ ! -f /etc/os-release ]]; then
        ui_err "/etc/os-release 缺失，无法识别操作系统。"
        exit 1
    fi
    # shellcheck disable=SC1091
    source /etc/os-release
    EWO_OS_ID="${ID:-unknown}"
    EWO_OS_VER="${VERSION_ID:-0}"
    EWO_OS_CODENAME="${VERSION_CODENAME:-}"
    export EWO_OS_ID EWO_OS_VER EWO_OS_CODENAME

    if [[ "${EWO_OS_ID}" != "debian" ]]; then
        ui_err "不支持的系统：${PRETTY_NAME:-${EWO_OS_ID}}。本安装器仅支持 Debian 12/13。"
        exit 1
    fi
    case "${EWO_OS_VER}" in
        12|13) ;;
        *)
            ui_err "不支持的 Debian 版本：${EWO_OS_VER}。请使用 Debian 12 (bookworm) 或 13 (trixie)。"
            exit 1 ;;
    esac
    ui_ok "已检测系统：Debian ${EWO_OS_VER} (${EWO_OS_CODENAME})"
}

precheck_clean_machine() {
    if [[ "${EWO_SKIP_PRECHECK:-0}" == "1" ]]; then
        ui_warn "EWO_SKIP_PRECHECK=1：已跳过「干净机器」检查（断点续装模式）"
        ui_warn "每个步骤都是幂等的；此模式仅用于上次失败后从中断处恢复。"
        return 0
    fi
    local conflicts=()
    for svc in mariadb mysql postfix dovecot nginx apache2 httpd; do
        if systemctl list-unit-files --type=service 2>/dev/null | grep -q "^${svc}\.service"; then
            if systemctl is-active --quiet "${svc}" 2>/dev/null; then
                conflicts+=("${svc}（正在运行）")
            fi
        fi
    done
    if dpkg -l 2>/dev/null | grep -E '^ii\s+(mariadb-server|mysql-server|postfix|dovecot-core|nginx-(core|full|light)|apache2)\s' >/dev/null 2>&1; then
        conflicts+=("已安装冲突的软件包")
    fi
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        ui_err "该 VPS 不是干净环境："
        for c in "${conflicts[@]}"; do ui_err "  - ${c}"; done
        ui_err ""
        ui_err "如需从上次失败的安装继续（仅限此情况），可执行："
        ui_err "  EWO_SKIP_PRECHECK=1 ./install/install.sh"
        ui_err ""
        ui_err "否则请重装 OS 或换一台 VPS。EwoMail-plus 独占整台机器。"
        exit 1
    fi
    ui_ok "机器环境干净（无冲突服务或软件包）"
}

precheck_resources() {
    EWO_MEM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    EWO_CPU_COUNT=$(nproc)
    EWO_DISK_AVAIL_G=$(df --output=avail -BG / | tail -1 | tr -dc '0-9')
    export EWO_MEM_KB EWO_CPU_COUNT EWO_DISK_AVAIL_G

    ui_info "已检测资源：${EWO_CPU_COUNT} 核 CPU / $(( EWO_MEM_KB / 1024 )) MB 内存 / 根分区剩余 ${EWO_DISK_AVAIL_G} GB"

    if (( EWO_DISK_AVAIL_G < 20 )); then
        ui_warn "根分区可用空间不足 20 GB；邮件存储 + ClamAV 病毒库可能不够用。"
    fi
}

prompt_swap() {
    # If RAM ≤ 2GB, offer to create a swap file. Amavis + ClamAV resident set
    # can reach ~1.5GB at peak; tight on 2GB without swap.
    local cur_swap_kb
    cur_swap_kb=$(awk '/SwapTotal/ {print $2}' /proc/meminfo)
    if (( EWO_MEM_KB > 2200 * 1024 )); then
        return 0     # plenty of RAM, swap unnecessary
    fi
    if (( cur_swap_kb >= 1024 * 1024 )); then
        ui_ok "已检测到 swap：$(( cur_swap_kb / 1024 )) MB（无需创建）"
        return 0
    fi
    local want_size=2
    (( EWO_MEM_KB > 1500 * 1024 )) && want_size=1
    ui_warn "本机内存 $(( EWO_MEM_KB / 1024 )) MB，amavis + ClamAV 高峰可能 OOM。"
    prompt_yesno "现在创建 ${want_size} GB swap 文件（/swapfile）？" "yes" cont
    if [[ "${cont}" == "yes" ]]; then
        setup_swap "${want_size}"
    else
        ui_info "已跳过 swap 创建，记得自己加上。"
    fi
}

setup_swap() {
    local gb="$1"
    ui_info "创建 ${gb} GB swap，请稍候……"
    if ! fallocate -l "${gb}G" /swapfile 2>>"${LOG_FILE}"; then
        # Fall back to dd if fallocate fails (e.g. on tmpfs/btrfs).
        run dd if=/dev/zero of=/swapfile bs=1M count=$(( gb * 1024 )) status=none
    fi
    chmod 0600 /swapfile
    run mkswap /swapfile
    run swapon /swapfile
    if ! grep -q '^/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    ui_ok "Swap 已启用：$(swapon --show=size,used --noheadings | tr '\n' ' ')"
}

prompt_domain() {
    while true; do
        prompt_default "主邮件域名（如 example.com，不要带 mail. 前缀）" "" EWO_DOMAIN
        if [[ -z "${EWO_DOMAIN}" ]]; then
            ui_warn "必须输入域名。"
            continue
        fi
        if [[ ! "${EWO_DOMAIN}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$ ]]; then
            ui_warn "格式不对，请输入 example.com 这样的纯域名。"
            continue
        fi
        if [[ "${EWO_DOMAIN}" == mail.* ]]; then
            ui_warn "不要带 'mail.' 前缀，安装器会自动加上去。"
            continue
        fi
        break
    done
    EWO_MAIL_HOST="mail.${EWO_DOMAIN}"
    export EWO_DOMAIN EWO_MAIL_HOST
    ui_ok "已设定域名：${EWO_DOMAIN}（邮件主机：${EWO_MAIL_HOST}）"
}

prompt_admin_email() {
    local default_email="admin@${EWO_DOMAIN}"
    while true; do
        prompt_default "管理员联系邮箱（Let's Encrypt 通知用）" "${default_email}" EWO_ADMIN_EMAIL
        # Conservative check: keep characters that are SQL-safe to interpolate
        # later (we use heredoc SQL in admin_init.sh).
        if [[ "${EWO_ADMIN_EMAIL}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            break
        fi
        ui_warn "邮箱格式不对，请重试。"
    done
    export EWO_ADMIN_EMAIL
}

prompt_db_admin_enabled() {
    prompt_yesno "对外开放 Adminer 数据库管理？（随机 URL 路径，后台可一键关闭）" "no" EWO_DB_ADMIN_ENABLED
    export EWO_DB_ADMIN_ENABLED
}

prompt_request_letsencrypt() {
    prompt_yesno "安装结束时是否申请 Let's Encrypt 证书？（DNS 需先指过来）" "yes" EWO_LE_REQUEST
    export EWO_LE_REQUEST
}

precheck_dns() {
    local domain="$1"
    ui_info "检查 DNS 记录……"
    local public_ip
    public_ip=$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)
    if [[ -z "${public_ip}" ]]; then
        public_ip=$(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || true)
    fi
    if [[ -z "${public_ip}" ]]; then
        ui_warn "无法自动获取公网 IPv4，DNS 校验将跳过。"
        return 0
    fi
    export EWO_PUBLIC_IP="${public_ip}"
    ui_ok "已检测公网 IPv4：${public_ip}"

    local a_record
    a_record=$(getent ahostsv4 "mail.${domain}" 2>/dev/null | awk '{print $1}' | head -1 || true)
    if [[ "${a_record}" == "${public_ip}" ]]; then
        ui_ok "mail.${domain} → ${a_record}（与本机一致）"
    elif [[ -n "${a_record}" ]]; then
        ui_warn "mail.${domain} 当前解析到 ${a_record}，但本机 IP 是 ${public_ip}。"
        ui_warn "请在 ${domain} 的 DNS 添加  ${UI_BOLD}A  mail   ${public_ip}${UI_RESET}  ，再重新运行本脚本。"
        prompt_yesno "仍继续？（安装可完成，但邮件在 DNS 生效前无法收发）" "no" cont
        [[ "${cont}" != "yes" ]] && { ui_err "已中止。"; exit 1; }
    else
        ui_warn "mail.${domain} 暂无 A 记录。"
        cat <<EOF
${UI_BOLD}请在 ${domain} 发布以下 DNS 记录${UI_RESET}（安装结束会再次打印准确值）：
  ${UI_CYAN}A      mail        ${public_ip}${UI_RESET}
  ${UI_CYAN}MX     @           mail.${domain}.   优先级 10${UI_RESET}
  ${UI_CYAN}TXT    @           v=spf1 mx ~all${UI_RESET}
  ${UI_CYAN}TXT    _dmarc      v=DMARC1; p=quarantine; rua=mailto:postmaster@${domain}${UI_RESET}
  ${UI_CYAN}TXT    dkim._domainkey   （DKIM 公钥安装后输出）${UI_RESET}
反向解析 (PTR) 需将 ${public_ip} 指向 mail.${domain}，到 VPS 厂商控制台设置。
EOF
        prompt_yesno "仍继续？（可以装完再加 DNS，邮件在 DNS 生效前不流动）" "yes" cont
        [[ "${cont}" != "yes" ]] && { ui_err "已中止。"; exit 1; }
    fi
}
