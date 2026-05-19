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
  (106, '数据导入/导出','数据导入/导出','/DataPort', 100, 0, 0, 0, 10),
  (207, 'Webmail 品牌','Webmail 品牌','/System/webmail-config', 200, 1, 0, 0, 40),
  (300, '服务器',  '服务器',   '',          0,   0, 0, 0, 50),
  (301, '防火墙',  '防火墙',   '/Firewall', 300, 1, 1, 0, 51),
  (302, 'Nginx',  'Nginx',     '/Nginx',    300, 1, 0, 0, 52),
  (303, 'SSL证书','SSL证书',   '/Cert',     300, 1, 0, 0, 53),
  (304, '面板设置','面板设置', '/Setting',  300, 1, 0, 0, 54);
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

-- i_day_record 在原 EwoMail install.sql 里漏掉了 —— 老版本是某个独立组件
-- 首次写入时才隐式建表，PHP 这边 Users.php 的"收发数量"页和清零按钮
-- 直接 SELECT/UPDATE 这张表。表不存在 → PDO 抛 Table doesn't exist →
-- E::sys 整页 500。schema 按 PHP 代码引用的列推出来。
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

    # 给 i_domains 里每条 active 域名写一份 SnappyMail .json，否则 webmail
    # 登录会被"no domain configuration"挡。i_domains 在前面 INSERT 进的
    # ${EWO_DOMAIN} 这条；后续在 admin 后台再加域名时由 Domain 保存逻辑
    # 通过 helper 同步，update.sh 也会重新跑一遍 sync。
    if [[ -d /ewomail/www/snappymail ]]; then
        run /ewomail/sbin/ewomail-helper snappy-domain-sync
    fi

    ui_ok "业务数据库已初始化；管理员账号 admin（密码见凭据文件）"
}
