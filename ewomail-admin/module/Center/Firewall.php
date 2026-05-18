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

/** Per-port description overrides from i_panel_setting.fw_port_descs (JSON). */
function _fw_custom_descs()
{
    $raw = Helper::setting('fw_port_descs', '');
    if ($raw === '') return [];
    $j = json_decode($raw, true);
    return is_array($j) ? $j : [];
}

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

    // 出方向被 REJECT 的端口（由 helper 解析 firewalld direct rules）
    $out_blocked = [];
    $ol = Helper::run(['fw-out-list']);
    if ($ol['ok']) {
        foreach (preg_split('/\s+/', trim($ol['out'])) as $p) {
            if ($p !== '') $out_blocked[$p] = true;
        }
    }

    $custom = _fw_custom_descs();

    // 先按 KNOWN_PORTS 顺序输出（含未开放的），再追加用户自定义端口；
    // 22/tcp/udp 全程过滤掉 —— UI 上完全看不到，避免误操作。
    $open_set = array_flip($ports_open);
    $port_rows = [];
    $build_row = function ($p, $default_desc, $known) use ($open_set, $out_blocked, $custom) {
        return [
            'port'     => $p,
            'desc'     => isset($custom[$p]) ? $custom[$p] : $default_desc,
            'in_open'  => isset($open_set[$p]),
            'out_open' => !isset($out_blocked[$p]),
            'known'    => $known,
        ];
    };
    foreach (KNOWN_PORTS as $p => $desc) {
        $port_rows[] = $build_row($p, $desc, true);
    }
    foreach ($ports_open as $p) {
        if ($p === '22/tcp' || $p === '22/udp') continue;
        if (isset(KNOWN_PORTS[$p])) continue;
        $port_rows[] = $build_row($p, '自定义端口', false);
    }
    // 出方向被堵但入方向未列在 KNOWN/open 里的端口也要展示，否则用户
    // 看不到这条规则的存在、没法解除。
    foreach (array_keys($out_blocked) as $p) {
        if ($p === '22/tcp' || $p === '22/udp') continue;
        $shown = false;
        foreach ($port_rows as $r) { if ($r['port'] === $p) { $shown = true; break; } }
        if (!$shown) $port_rows[] = $build_row($p, '仅出方向已被封禁', false);
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

// ---- 出方向端口开关 ----
Rout::put('out-add', function () {
    $val = trim(ipost('port'));
    if (!Helper::validatePortProto($val)) E::error('格式：1234/tcp 或 1234/udp');
    $r = Helper::run(['fw-out-add', $val]);
    $r['ok'] ? E::success('出方向已封禁：' . $val) : E::error('失败：' . $r['out']);
});

Rout::put('out-del', function () {
    $val = trim(ipost('port'));
    if (!Helper::validatePortProto($val)) E::error('格式：1234/tcp 或 1234/udp');
    $r = Helper::run(['fw-out-del', $val]);
    $r['ok'] ? E::success('出方向已恢复：' . $val) : E::error('失败：' . $r['out']);
});

// ---- 编辑端口说明（写入 i_panel_setting.fw_port_descs JSON）----
Rout::put('desc-save', function () {
    $port = trim(ipost('port'));
    $desc = trim(ipost('desc'));
    if (!Helper::validatePortProto($port)) E::error('端口格式无效');
    // 防止超大输入或注入控制字符到 JSON；保留多语言文本即可。
    if (mb_strlen($desc) > 200) E::error('说明太长（最多 200 字符）');
    if (preg_match('/[\x00-\x1f\x7f]/', $desc)) E::error('说明含非法控制字符');

    $custom = _fw_custom_descs();
    if ($desc === '') {
        unset($custom[$port]);  // 清空 = 恢复默认
    } else {
        $custom[$port] = $desc;
    }
    $json = json_encode($custom, JSON_UNESCAPED_UNICODE);
    if (!Helper::settingSet('fw_port_descs', $json)) {
        E::error('保存失败');
    }
    E::success('说明已更新');
});
