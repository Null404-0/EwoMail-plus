# Apply DB schema, configure admin panel: random URL paths, admin password,
# privilege helper script, sudoers entry.

init_application_db() {
    # Render PHP config first so the init helper can connect.
    render_template "${INSTALLER_DIR}/templates/snappymail/admin-config.php" /ewomail/www/ewomail-admin/core/config.php
    chmod 0440 /ewomail/www/ewomail-admin/core/config.php
    chown www-data:www-data /ewomail/www/ewomail-admin/core/config.php

    # Load base schema + per-installation overrides.
    local sql="/ewomail/www/ewomail-admin/upload/install.sql"
    if [[ -f "${sql}" ]]; then
        run mysql -uroot ewomail -e "SET NAMES utf8mb4;"
        run mysql -uroot ewomail < "${sql}"
        rm -f "${sql}"
    else
        ui_warn "install.sql 不存在（可能已导入过），跳过 schema 加载。"
    fi

    # Per-domain init.
    mysql -uroot ewomail <<EOF
INSERT INTO i_domains (name, active, ctime)
SELECT '${EWO_DOMAIN}', 1, NOW()
WHERE NOT EXISTS (SELECT 1 FROM i_domains WHERE name='${EWO_DOMAIN}');

UPDATE i_mail_config SET value='imap.${EWO_DOMAIN}'  WHERE name='imap';
UPDATE i_mail_config SET value='smtp.${EWO_DOMAIN}'  WHERE name='smtp';
UPDATE i_mail_config SET value='${EWO_DOMAIN}'       WHERE name='mydomain';
UPDATE i_mail_config SET value='${EWO_MAIL_HOST}'    WHERE name='myhostname';

UPDATE i_admin SET password = MD5('${EWO_ADMIN_PWD}') WHERE aid=1;
EOF

    # Menu entries for the new Server modules (Firewall/Nginx/SSL/Settings).
    # mark fields use 'Server.*' just as identifiers; the panel renders them
    # as the `mark` column directly when no L() lookup is present.
    mysql -uroot ewomail <<EOF
INSERT IGNORE INTO i_admin_menu (menu_id, mark, lang, url, top_id, edit, del, edit_id, sort) VALUES
  (300, 'Server',   'Server',   '',         0,   0, 0, 0, 50),
  (301, 'Firewall', 'Firewall', '/Firewall', 300, 1, 1, 0, 51),
  (302, 'Nginx',    'Nginx',    '/Nginx',    300, 1, 0, 0, 52),
  (303, 'SSL',      'SSL',      '/Cert',     300, 1, 0, 0, 53),
  (304, 'Settings', 'Settings', '/Setting',  300, 1, 0, 0, 54);
EOF

    # Persist runtime settings the panel reads back (URL paths, DB toggle).
    mysql -uroot ewomail <<EOF
CREATE TABLE IF NOT EXISTS i_panel_setting (
    name  VARCHAR(64) PRIMARY KEY,
    value TEXT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
REPLACE INTO i_panel_setting VALUES
  ('admin_path',      '${EWO_ADMIN_PATH}'),
  ('db_path',         '${EWO_DB_PATH}'),
  ('db_admin_enable', '${EWO_DB_ADMIN_ENABLED}'),
  ('mail_host',       '${EWO_MAIL_HOST}'),
  ('public_ip',       '${EWO_PUBLIC_IP:-}'),
  ('le_email',        '${EWO_ADMIN_EMAIL}');
EOF

    # Privilege helper used by Firewall/Nginx/Cert modules.
    install -d -m 0750 -o root -g www-data /ewomail/sbin
    render_template "${INSTALLER_DIR}/templates/admin-helper/ewomail-helper" /ewomail/sbin/ewomail-helper
    chmod 0750 /ewomail/sbin/ewomail-helper
    chown root:www-data /ewomail/sbin/ewomail-helper

    # Sudoers — restrict www-data to exactly this helper, nothing else.
    # /etc/sudoers.d is shipped by the sudo package; defensively recreate it
    # in case the install ordering was unusual.
    install -d -m 0750 -o root -g root /etc/sudoers.d
    cat > /etc/sudoers.d/ewomail <<EOF
www-data ALL=(root) NOPASSWD: /ewomail/sbin/ewomail-helper
Defaults!/ewomail/sbin/ewomail-helper !requiretty
EOF
    chmod 0440 /etc/sudoers.d/ewomail
    run visudo -cf /etc/sudoers.d/ewomail

    ui_ok "业务数据库已初始化；管理员账号 admin（密码见凭据文件）"
}
