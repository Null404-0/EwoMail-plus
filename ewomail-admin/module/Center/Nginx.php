<?php
/**
 * Nginx: visual vhost management.
 */
if (!defined('PATH')) exit;

Rout::get('index', function () {
    Admin::setMenu(302, 'Nginx');

    $list = Helper::run(['nginx-list']);
    $sites = [];
    if ($list['ok']) {
        foreach (preg_split('/\r?\n/', $list['out']) as $line) {
            $line = trim($line);
            if ($line !== '' && Helper::validateSiteName($line)) {
                $sites[] = [
                    'name'    => $line,
                    'enabled' => file_exists('/etc/nginx/sites-enabled/' . $line),
                ];
            }
        }
    }

    $test = Helper::run(['nginx-test']);

    Tp::assign([
        'sites'    => $sites,
        'test_out' => $test['out'],
        'test_ok'  => $test['ok'],
    ]);
    Tp::display();
});

Rout::get('edit', function () {
    Admin::setMenu(302, 'Nginx');
    $name = trim(iget('name'));
    if (!Helper::validateSiteName($name)) E::error('Invalid site name');
    $r = Helper::run(['nginx-cat', $name]);
    if (!$r['ok']) E::error('Cannot read: ' . $r['out']);

    Tp::assign([
        'name'    => $name,
        'content' => $r['out'],
    ]);
    Tp::display();
});

Rout::post('save', function () {
    $name    = trim(ipost('name'));
    $content = ipost('content');
    if (!Helper::validateSiteName($name)) E::error('Invalid site name');
    if (!is_string($content) || $content === '') E::error('Content is empty');

    $r = Helper::run(['nginx-save', $name], $content);
    $r['ok'] ? E::success('Saved & reloaded') : E::error('nginx-t failed: ' . $r['out']);
});

Rout::post('reload', function () {
    $r = Helper::run(['nginx-reload']);
    $r['ok'] ? E::success('Reloaded') : E::error($r['out']);
});

Rout::post('test', function () {
    $r = Helper::run(['nginx-test']);
    $r['ok'] ? E::success($r['out'] ?: 'syntax OK') : E::error($r['out']);
});

Rout::post('enable', function () {
    $name = trim(ipost('name'));
    if (!Helper::validateSiteName($name)) E::error('Invalid site name');
    $r = Helper::run(['nginx-enable', $name]);
    $r['ok'] ? E::success('Enabled: ' . $name) : E::error($r['out']);
});

Rout::post('disable', function () {
    $name = trim(ipost('name'));
    if (!Helper::validateSiteName($name)) E::error('Invalid site name');
    $r = Helper::run(['nginx-disable', $name]);
    $r['ok'] ? E::success('Disabled: ' . $name) : E::error($r['out']);
});
