<?php
/**
 * Firewall: visual firewalld management (bt-style).
 */
if (!defined('PATH')) exit;

// 邮件服务相关的常用端口。即使当前没在防火墙里开，也列出来让管理员
// 看到状态 + 一键开启。22/tcp 故意不在这里 —— UI 不允许操作，避免
// 没有外层安全组的 VPS 不小心切到自己 SSH。
const KNOWN_PORTS = [
    '25/tcp'  => 'SMTP 收信（外网投递必须开）',
    '80/tcp'  => 'HTTP（acme.sh 申请 / 续签 SSL 必须开）',
    '443/tcp' => 'HTTPS（网页 / 管理后台 / Webmail）',
    '465/tcp' => 'SMTPS 提交（客户端发信，TLS）',
    '587/tcp' => 'Submission 提交（客户端发信，STARTTLS）',
    '993/tcp' => 'IMAPS 收信（客户端读信，TLS）',
    '995/tcp' => 'POP3S 收信（客户端读信，TLS）',
    '143/tcp' => 'IMAP 收信（客户端读信，明文 / STARTTLS）',
    '110/tcp' => 'POP3 收信（客户端读信，明文 / STARTTLS）',
];

Rout::get('index', function () {
    Admin::setMenu(301, '防火墙');

    $list = Helper::run(['fw-list']);

    // Parse firewall-cmd --list-all output into structured arrays.
    $ports_open = []; $rejects = [];
    if ($list['ok']) {
        if (preg_match('/ports:\s*([^\n]*)/', $list['out'], $m)) {
            $ports_open = array_values(array_filter(preg_split('/\s+/', trim($m[1]))));
        }
        if (preg_match('/rich rules:(.+?)(?:\n\w|\Z)/s', $list['out'], $m)) {
            foreach (preg_split('/\n/', trim($m[1])) as $line) {
                if (preg_match('/source address="([0-9.]+)" reject/', $line, $mm)) {
                    $rejects[] = $mm[1];
                }
            }
        }
    }

    // 先按 KNOWN_PORTS 顺序输出（含未开放的），再追加用户自定义端口；
    // 22/tcp/udp 全程过滤掉 —— UI 上完全看不到，避免误操作。
    $open_set = array_flip($ports_open);
    $port_rows = [];
    foreach (KNOWN_PORTS as $p => $desc) {
        $port_rows[] = ['port' => $p, 'desc' => $desc, 'open' => isset($open_set[$p]), 'known' => true];
    }
    foreach ($ports_open as $p) {
        if ($p === '22/tcp' || $p === '22/udp') continue;
        if (isset(KNOWN_PORTS[$p])) continue;
        $port_rows[] = ['port' => $p, 'desc' => '自定义端口', 'open' => true, 'known' => false];
    }

    $st = Helper::run(['outbound-status']);
    $outbound_disabled = trim($st['out']) === 'yes';

    Tp::assign([
        'raw'               => $list['out'],
        'ok'                => $list['ok'],
        'port_rows'         => $port_rows,
        'blocked'           => $rejects,
        'outbound_disabled' => $outbound_disabled,
    ]);
    Tp::display();
});

Rout::put('outbound-disable', function () {
    $r = Helper::run(['outbound-disable']);
    $r['ok'] ? E::success('已关闭外发邮件（出站 25/tcp REJECT + 入站 465/587 关闭）') : E::error($r['out']);
});

Rout::put('outbound-enable', function () {
    $r = Helper::run(['outbound-enable']);
    $r['ok'] ? E::success('已恢复外发邮件') : E::error($r['out']);
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
