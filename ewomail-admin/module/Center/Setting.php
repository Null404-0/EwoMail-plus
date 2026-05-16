<?php
/**
 * Setting: random paths, DB-admin entry toggle, change admin password.
 */
if (!defined('PATH')) exit;

Rout::get('index', function () {
    Admin::setMenu(304, 'Settings');

    Tp::assign([
        'admin_path'   => Helper::setting('admin_path'),
        'db_path'      => Helper::setting('db_path'),
        'db_enabled'   => Helper::setting('db_admin_enable') === 'yes',
        'mail_host'    => Helper::setting('mail_host'),
        'public_ip'    => Helper::setting('public_ip'),
    ]);
    Tp::display();
});

Rout::post('rotate-admin-path', function () {
    $r = Helper::run(['setting-rotate-admin-path']);
    if (!$r['ok']) E::error($r['out']);
    $new = trim($r['out']);
    E::success('New admin path: /' . $new . '/  — log in again on the new URL.', '', ['path' => $new]);
});

Rout::post('rotate-db-path', function () {
    $r = Helper::run(['setting-rotate-db-path']);
    if (!$r['ok']) E::error($r['out']);
    $new = trim($r['out']);
    E::success('New db path: /' . $new . '/', '', ['path' => $new]);
});

Rout::post('toggle-db', function () {
    $val = ipost('state') === 'on' ? 'on' : 'off';
    $r = Helper::run(['setting-toggle-db', $val]);
    $r['ok'] ? E::success('Adminer is now ' . $val) : E::error($r['out']);
});

Rout::post('change-password', function () {
    $cur = (string) ipost('current');
    $new = (string) ipost('new');
    $confirm = (string) ipost('confirm');

    if (Admin::$info['password'] !== md5($cur)) {
        E::error('Current password is wrong.');
    }
    if (strlen($new) < 12) {
        E::error('New password must be at least 12 characters.');
    }
    if ($new !== $confirm) {
        E::error('Confirmation does not match.');
    }
    App::$db->query(
        "UPDATE i_admin SET password='" . md5($new) . "' WHERE aid=" . intval(Admin::$aid)
    );
    E::success('Password changed. Log in again.', U('/Index/out'));
});
