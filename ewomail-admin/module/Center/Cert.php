<?php
/**
 * Cert: one-click Let's Encrypt issuance/renewal via acme.sh.
 */
if (!defined('PATH')) exit;

Rout::get('index', function () {
    Admin::setMenu(303, 'SSL');

    $list = Helper::run(['cert-list']);
    $rows = [];
    if ($list['ok']) {
        // Header line first, skip it.
        $lines = preg_split('/\r?\n/', trim($list['out']));
        foreach ($lines as $i => $line) {
            if ($i === 0 || $line === '') continue;
            $cols = preg_split('/\s+/', $line, 7);
            if (count($cols) >= 3) {
                $rows[] = [
                    'domain'  => $cols[0],
                    'ca'      => isset($cols[2]) ? $cols[2] : '',
                    'created' => isset($cols[3]) ? $cols[3] : '',
                    'renew'   => isset($cols[4]) ? $cols[4] : '',
                ];
            }
        }
    }

    // Live nginx cert info (file mtime + subject from openssl)
    $live = [];
    $crt = '/etc/ssl/ewomail/fullchain.pem';
    if (is_readable($crt)) {
        $out = shell_exec('openssl x509 -in ' . escapeshellarg($crt) . ' -noout -subject -enddate 2>/dev/null');
        $live = [
            'path' => $crt,
            'info' => trim($out ?: 'unknown'),
            'mtime'=> date('Y-m-d H:i', filemtime($crt)),
        ];
    }

    Tp::assign([
        'rows'      => $rows,
        'mail_host' => Helper::setting('mail_host'),
        'live'      => $live,
    ]);
    Tp::display();
});

Rout::post('issue', function () {
    $d = trim(ipost('domain'));
    if (!Helper::validateFqdn($d)) E::error('Invalid FQDN');
    $r = Helper::run(['cert-issue', $d]);
    $r['ok'] ? E::success('Issued; click "Install" to deploy.') : E::error('acme.sh: ' . $r['out']);
});

Rout::post('renew', function () {
    $d = trim(ipost('domain'));
    if (!Helper::validateFqdn($d)) E::error('Invalid FQDN');
    $r = Helper::run(['cert-renew', $d]);
    $r['ok'] ? E::success('Renewed.') : E::error('acme.sh: ' . $r['out']);
});

Rout::post('install', function () {
    $d = trim(ipost('domain'));
    if (!Helper::validateFqdn($d)) E::error('Invalid FQDN');
    $r = Helper::run(['cert-install', $d]);
    $r['ok'] ? E::success('Installed; services reloaded.') : E::error($r['out']);
});
