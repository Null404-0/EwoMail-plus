<?php
/**
 * Firewall: visual firewalld management (bt-style).
 */
if (!defined('PATH')) exit;

Rout::get('index', function () {
    Admin::setMenu(301, '防火墙');

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
    if (!Helper::validatePortProto($val)) E::error('格式：1234/tcp 或 1234/udp');
    $r = Helper::run(['fw-add', $val]);
    $r['ok'] ? E::success('端口已开放：' . $val) : E::error('失败：' . $r['out']);
});

Rout::put('port-del', function () {
    $val = trim(ipost('port'));
    if (!Helper::validatePortProto($val)) E::error('格式：1234/tcp 或 1234/udp');
    $r = Helper::run(['fw-del', $val]);
    $r['ok'] ? E::success('端口已关闭：' . $val) : E::error('失败：' . $r['out']);
});

Rout::put('block', function () {
    $ip = trim(ipost('ip'));
    if (!Helper::validateIPv4($ip)) E::error('IP 格式无效');
    $r = Helper::run(['fw-block', $ip]);
    $r['ok'] ? E::success('已封禁：' . $ip) : E::error('失败：' . $r['out']);
});

Rout::put('unblock', function () {
    $ip = trim(ipost('ip'));
    if (!Helper::validateIPv4($ip)) E::error('IP 格式无效');
    $r = Helper::run(['fw-unblock', $ip]);
    $r['ok'] ? E::success('已解封：' . $ip) : E::error('失败：' . $r['out']);
});

Rout::put('reload', function () {
    $r = Helper::run(['fw-reload']);
    $r['ok'] ? E::success('已重载') : E::error($r['out']);
});
