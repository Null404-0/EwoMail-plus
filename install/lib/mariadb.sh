# MariaDB hardening + EwoMail database creation.

setup_mariadb() {
    run systemctl start mariadb

    # systemctl start returns once the unit is "active", but mariadb may need
    # an extra moment before the local socket accepts queries. Poll for up to
    # 30s — faster than guessing a fixed sleep on a slow VPS.
    local tries=0
    until mariadb-admin -uroot ping --silent >/dev/null 2>&1 \
       || mysqladmin     -uroot ping --silent >/dev/null 2>&1; do
        tries=$(( tries + 1 ))
        if (( tries > 30 )); then
            ui_err "MariaDB did not become reachable within 30s"
            systemctl status mariadb --no-pager >>"${LOG_FILE}" 2>&1 || true
            return 1
        fi
        sleep 1
    done

    # Set root password and remove anonymous users / test DB. Use unix-socket
    # plugin first to ensure idempotent local root access.
    local sql_init
    sql_init=$(mktemp); chmod 600 "${sql_init}"
    cat > "${sql_init}" <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${EWO_MYSQL_ROOT_PWD}';
DELETE FROM mysql.global_priv WHERE User='';
DELETE FROM mysql.global_priv WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
    run mysql -uroot < "${sql_init}"
    rm -f "${sql_init}"

    # Drop a root .my.cnf so the installer (and helper scripts) can run client.
    cat > /root/.my.cnf <<EOF
[client]
user=root
password=${EWO_MYSQL_ROOT_PWD}
EOF
    chmod 600 /root/.my.cnf

    # Create application user.
    mysql -uroot <<EOF
CREATE DATABASE IF NOT EXISTS ewomail DEFAULT CHARSET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'ewomail'@'localhost' IDENTIFIED BY '${EWO_MYSQL_EWOMAIL_PWD}';
CREATE USER IF NOT EXISTS 'ewomail'@'127.0.0.1' IDENTIFIED BY '${EWO_MYSQL_EWOMAIL_PWD}';
ALTER USER 'ewomail'@'localhost' IDENTIFIED BY '${EWO_MYSQL_EWOMAIL_PWD}';
ALTER USER 'ewomail'@'127.0.0.1' IDENTIFIED BY '${EWO_MYSQL_EWOMAIL_PWD}';
GRANT ALL PRIVILEGES ON ewomail.* TO 'ewomail'@'localhost';
GRANT ALL PRIVILEGES ON ewomail.* TO 'ewomail'@'127.0.0.1';
FLUSH PRIVILEGES;
EOF
    ui_ok "MariaDB ready, root and ewomail users configured"
}
