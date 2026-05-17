<?php
/**
 * Firewall: visual firewalld management (bt-style).
 */
if (!defined('PATH')) exit;

Rout::get('index', function () {
    Admin::setMenu(301, 'Firewall');

    $list = Helper::run(['fw-list']);

    // Parse firewall-cmd --list-all output into structured arrays.
    $ports = []; $rejects = []; $allowlist = [];
    if ($list['ok']) {
        if (preg_match('/ports:\s*([^\n]*)/', $list['out'], $m)) {
            $ports = array_values(array_filter(preg_split('/\s+/', trim($m[1]))));
        }
        if (preg_match('/rich rules:(.+?)(?:\n\w|\Z)/s', $list['out'], $m)) {
            foreach (preg_split('/\n/', trim($m[1])) as $line) {
                if (preg_match('/source address="([0-9.]+)" reject/', $line, $mm)) {
                    $rejects[] = $mm[1];
                }
            }
        }
    }

    Tp::assign([
        'raw'        => $list['out'],
        'ok'         => $list['ok'],
        'ports'      => $ports,
        'blocked'    => $rejects,
    ]);
    Tp::display();
});

Rout::put('port-add', function () {
    $val = trim(ipost('port'));
    if (!Helper::validatePortProto($val)) E::error('Format: 1234/tcp or 1234/udp');
    $r = Helper::run(['fw-add', $val]);
    $r['ok'] ? E::success('Port opened: ' . $val) : E::error('Failed: ' . $r['out']);
});

Rout::put('port-del', function () {
    $val = trim(ipost('port'));
    if (!Helper::validatePortProto($val)) E::error('Format: 1234/tcp or 1234/udp');
    $r = Helper::run(['fw-del', $val]);
    $r['ok'] ? E::success('Port closed: ' . $val) : E::error('Failed: ' . $r['out']);
});

Rout::put('block', function () {
    $ip = trim(ipost('ip'));
    if (!Helper::validateIPv4($ip)) E::error('Invalid IPv4');
    $r = Helper::run(['fw-block', $ip]);
    $r['ok'] ? E::success('Blocked: ' . $ip) : E::error('Failed: ' . $r['out']);
});

Rout::put('unblock', function () {
    $ip = trim(ipost('ip'));
    if (!Helper::validateIPv4($ip)) E::error('Invalid IPv4');
    $r = Helper::run(['fw-unblock', $ip]);
    $r['ok'] ? E::success('Unblocked: ' . $ip) : E::error('Failed: ' . $r['out']);
});

Rout::put('reload', function () {
    $r = Helper::run(['fw-reload']);
    $r['ok'] ? E::success('Reloaded') : E::error($r['out']);
});
