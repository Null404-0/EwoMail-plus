# firewalld: define an "ewomail" zone containing exactly the public mail+web
# ports, set it as the default for the public interface.

setup_firewall() {
    run systemctl enable --now firewalld
    # Wait briefly for firewalld dbus.
    for _ in 1 2 3 4 5; do
        if firewall-cmd --state >>"${LOG_FILE}" 2>&1; then break; fi
        sleep 1
    done

    if firewall-cmd --get-zones | grep -qw ewomail; then
        ui_info "firewalld zone 'ewomail' already exists; reconfiguring"
        run firewall-cmd --permanent --delete-zone=ewomail
        run firewall-cmd --reload
    fi
    run firewall-cmd --permanent --new-zone=ewomail
    run firewall-cmd --permanent --zone=ewomail --set-target=default

    # SSH is critical — assume sshd listens on 22 unless customized.
    local ssh_port
    ssh_port=$(awk '/^Port[[:space:]]+/ {print $2; exit}' /etc/ssh/sshd_config 2>/dev/null || true)
    ssh_port="${ssh_port:-22}"

    local ports=("${ssh_port}/tcp" 80/tcp 443/tcp 25/tcp 465/tcp 587/tcp 993/tcp 995/tcp 143/tcp 110/tcp)
    for p in "${ports[@]}"; do
        run firewall-cmd --permanent --zone=ewomail --add-port="${p}"
    done

    # Pin the active interface(s) to the ewomail zone, but DO NOT change the
    # default; we leave 'public' as default to keep ssh reachable if something
    # is misconfigured.
    local iface
    iface=$(ip -o -4 route show default 2>/dev/null | awk '{print $5}' | head -1)
    if [[ -n "${iface}" ]]; then
        run firewall-cmd --permanent --zone=ewomail --add-interface="${iface}"
    fi
    run firewall-cmd --reload
    ui_ok "firewalld zone 'ewomail' active (ports: ${ports[*]})"
}
