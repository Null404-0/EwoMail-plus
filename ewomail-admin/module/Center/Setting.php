<?php
/**
 * Setting: random paths, DB-admin entry toggle, change admin password.
 */
if (!defined('PATH')) exit;

Rout::get('index', function () {
    Admin::setMenu(304, '面板设置');

    Tp::assign([
        'admin_path'   => Helper::setting('admin_path'),
        'db_path'      => Helper::setting('db_path'),
        'db_enabled'   => Helper::setting('db_admin_enable') === 'yes',
        'mail_host'    => Helper::setting('mail_host'),
        'public_ip'    => Helper::setting('public_ip'),
    ]);
    Tp::display();
});

Rout::put('rotate-admin-path', function () {
    $r = Helper::run(['setting-rotate-admin-path']);
    if (!$r['ok']) E::error($r['out']);
    $new = trim($r['out']);
    E::success('新的管理路径：/' . $new . '/  — 请在新地址重新登录。', '', ['path' => $new]);
});

Rout::put('rotate-db-path', function () {
    $r = Helper::run(['setting-rotate-db-path']);
    if (!$r['ok']) E::error($r['out']);
    $new = trim($r['out']);
    E::success('新的数据库路径：/' . $new . '/', '', ['path' => $new]);
});

Rout::put('toggle-db', function () {
    $val = ipost('state') === 'on' ? 'on' : 'off';
    $r = Helper::run(['setting-toggle-db', $val]);
    $r['ok'] ? E::success('Adminer 已设为 ' . ($val === 'on' ? '启用' : '关闭')) : E::error($r['out']);
});

Rout::put('change-password', function () {
    $cur = (string) ipost('current');
    $new = (string) ipost('new');
    $confirm = (string) ipost('confirm');

    if (Admin::$info['password'] !== md5($cur)) {
        E::error('当前密码不正确。');
    }
    if (strlen($new) < 12) {
        E::error('新密码至少 12 位。');
    }
    if ($new !== $confirm) {
        E::error('两次输入不一致。');
    }
    App::$db->query(
        "UPDATE i_admin SET password='" . md5($new) . "' WHERE aid=" . intval(Admin::$aid)
    );
    E::success('密码已修改，请重新登录。', U('/Index/out'));
});
