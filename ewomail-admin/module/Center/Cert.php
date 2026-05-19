<?php
/**
 * Cert: one-click Let's Encrypt issuance/renewal via acme.sh.
 */
if (!defined('PATH')) exit;

Rout::get('index', function () {
    Admin::setMenu(303, 'SSL证书');

    $list = Helper::run(['cert-list']);
    $rows = [];
    if ($list['ok']) {
        // --listraw 输出形如：
        //   Main_Domain|KeyLength|SAN_Domains|CA|Created|Renew     (旧版)
        //   Main_Domain|KeyLength|SAN_Domains|Profile|CA|Created|Renew (新版多 Profile)
        // 用 header 行确定列位置，未来再加列也不会错位。
        $header = null;
        foreach (preg_split('/\r?\n/', trim($list['out'])) as $line) {
            $line = trim($line);
            if ($line === '') continue;
            $cols = explode('|', $line);
            if ($header === null && stripos($line, 'Main_Domain') === 0) {
                $header = array_flip(array_map('trim', $cols));
                continue;
            }
            $domain = isset($cols[0]) ? rtrim($cols[0], " \t.") : '';
            if (!Helper::validateFqdn($domain)) continue;
            $idx = function ($name, $fallback) use ($header) {
                return $header && isset($header[$name]) ? $header[$name] : $fallback;
            };
            $rows[] = [
                'domain'  => $domain,
                'ca'      => trim((string)($cols[$idx('CA',      3)] ?? ''), " \"'"),
                'created' => trim((string)($cols[$idx('Created', 4)] ?? '')),
                'renew'   => trim((string)($cols[$idx('Renew',   5)] ?? '')),
            ];
        }
    }

    // 通过 helper 读当前部署证书的信息（PHP 受 open_basedir 限制，无法
    // 直接访问 /etc/ssl/ewomail/fullchain.pem）。
    $live = [];
    $cur  = Helper::run(['cert-current']);
    if ($cur['ok'] && trim($cur['out']) !== '' && strpos($cur['out'], 'missing') === false) {
        $info = '';
        $mt   = 0;
        foreach (preg_split('/\r?\n/', $cur['out']) as $ln) {
            if (preg_match('/^mtime=(\d+)/', $ln, $m)) { $mt = (int)$m[1]; continue; }
            if ($ln !== '') $info .= $ln . "\n";
        }
        $live = [
            'path'  => '/etc/ssl/ewomail/fullchain.pem',
            'info'  => trim($info),
            'mtime' => $mt ? date('Y-m-d H:i', $mt) : '',
        ];
    }

    Tp::assign([
        'rows'      => $rows,
        'mail_host' => Helper::setting('mail_host'),
        'live'      => $live,
    ]);
    Tp::display();
});

Rout::put('issue', function () {
    $d = trim(ipost('domain'));
    if (!Helper::validateFqdn($d)) E::error('域名格式无效');
    $r = Helper::run(['cert-issue', $d]);
    // acme.sh 在「证书有效且不到续签时间」时会输出 "Domains not changed."
    // 并返回非 0 退出码——这其实不是失败，给一个友好的提示。
    if (!$r['ok'] && (strpos($r['out'], 'Domains not changed') !== false
                      || strpos($r['out'], 'Skipping') !== false)) {
        E::error('该域名已有未到期的证书，无需重新申请。如需强制更新，请使用下方表格里的「续签」按钮。');
    }
    // helper 在本地已有该证书时打了 reusing-existing-cert 标记，意味着
    // 跳过了 --issue 直接做了 install——给用户一个更准确的提示文案。
    if ($r['ok'] && strpos($r['out'], 'reusing-existing-cert') !== false) {
        E::success('已复用并部署现有证书。');
    } elseif ($r['ok']) {
        E::success('已签发，请点击「安装」部署到 Nginx/Postfix/Dovecot。');
    } else {
        E::error('acme.sh: ' . $r['out']);
    }
});

Rout::put('renew', function () {
    $d = trim(ipost('domain'));
    if (!Helper::validateFqdn($d)) E::error('域名格式无效');
    $r = Helper::run(['cert-renew', $d]);
    if ($r['ok']) {
        E::success('已检查续签状态，并部署当前证书。');
    } elseif (strpos($r['out'], 'Skip') !== false
              || strpos($r['out'], 'Next renewal time') !== false
              || strpos($r['out'], 'not due') !== false) {
        // 证书还没到 acme.sh 默认的 60 天续签窗口，--renew 返回非零；
        // 这不是失败——重新跑 cert-install 把现有证书铺一遍即可。
        $install = Helper::run(['cert-install', $d]);
        $install['ok']
            ? E::success('证书尚未到续签时间，已重新部署当前证书。')
            : E::error('acme.sh: ' . $r['out']);
    } else {
        E::error('acme.sh: ' . $r['out']);
    }
});

Rout::get('backup', function () {
    $cur = Helper::run(['cert-current']);
    if (!$cur['ok'] || trim($cur['out']) === '' || strpos($cur['out'], 'missing') !== false) {
        E::error('尚未部署证书，无法备份。');
    }

    while (ob_get_level()) ob_end_clean();
    $filename = 'ewomail-ssl-backup-' . date('Ymd-His') . '.tar.gz';
    header('Content-Type: application/gzip');
    header('Content-Disposition: attachment; filename="' . $filename . '"');
    header('Cache-Control: no-store, no-cache, must-revalidate');
    header('Pragma: no-cache');
    $err = '';
    $rc = Helper::stream(['cert-backup'], $err);
    if ($rc !== 0) {
        // Headers may already be sent; the precheck above should make this rare.
        error_log('cert-backup failed (rc=' . $rc . '): ' . $err);
    }
    exit;
});

Rout::put('restore', function () {
    if (empty($_FILES['backup']) || !isset($_FILES['backup']['tmp_name'])) {
        E::error('请选择证书备份文件。');
    }
    $f = $_FILES['backup'];
    if (!empty($f['error'])) {
        E::error('上传失败，错误码：' . $f['error']);
    }
    if (!is_uploaded_file($f['tmp_name'])) {
        E::error('上传文件无效。');
    }
    if ((int)$f['size'] <= 0 || (int)$f['size'] > 1024 * 1024) {
        E::error('备份文件大小异常，请上传 1MB 以内的 .tar.gz 文件。');
    }
    $data = file_get_contents($f['tmp_name']);
    if ($data === false || $data === '') {
        E::error('读取上传文件失败。');
    }
    $r = Helper::run(['cert-restore'], $data);
    $r['ok'] ? E::success('证书已恢复并重载 Nginx/Postfix/Dovecot。') : E::error('恢复失败：' . $r['out']);
});

Rout::put('install', function () {
    $d = trim(ipost('domain'));
    if (!Helper::validateFqdn($d)) E::error('域名格式无效');
    $r = Helper::run(['cert-install', $d]);
    $r['ok'] ? E::success('已部署，相关服务已重载。') : E::error($r['out']);
});
