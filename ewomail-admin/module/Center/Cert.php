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
        // --listraw format: Main_Domain|KeyLength|SAN_Domains|CA|Created|Renew
        // The first line is the header; skip it.
        $lines = preg_split('/\r?\n/', trim($list['out']));
        foreach ($lines as $i => $line) {
            if ($i === 0 || $line === '') continue;
            $cols = explode('|', $line);
            if (count($cols) >= 6) {
                $rows[] = [
                    'domain'  => $cols[0],
                    'ca'      => $cols[3],
                    'created' => $cols[4],
                    'renew'   => $cols[5],
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

Rout::put('issue', function () {
    $d = trim(ipost('domain'));
    if (!Helper::validateFqdn($d)) E::error('Invalid FQDN');
    $r = Helper::run(['cert-issue', $d]);
    $r['ok'] ? E::success('Issued; click "Install" to deploy.') : E::error('acme.sh: ' . $r['out']);
});

Rout::put('renew', function () {
    $d = trim(ipost('domain'));
    if (!Helper::validateFqdn($d)) E::error('Invalid FQDN');
    $r = Helper::run(['cert-renew', $d]);
    $r['ok'] ? E::success('Renewed.') : E::error('acme.sh: ' . $r['out']);
});

Rout::put('install', function () {
    $d = trim(ipost('domain'));
    if (!Helper::validateFqdn($d)) E::error('Invalid FQDN');
    $r = Helper::run(['cert-install', $d]);
    $r['ok'] ? E::success('Installed; services reloaded.') : E::error($r['out']);
});
