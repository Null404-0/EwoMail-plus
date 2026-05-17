<?php
/**
 * Nginx: visual vhost management.
 */
if (!defined('PATH')) exit;

Rout::get('index', function () {
    Admin::setMenu(302, 'Nginx');
    // 菜单名保留 Nginx（专有名词）；UI 文案用中文。

    $list = Helper::run(['nginx-list']);
    $sites = [];
    if ($list['ok']) {
        // 新格式：每行 "<name>\t<enabled|disabled>"
        // PHP-FPM 受 open_basedir 限制无法直接看 /etc/nginx/sites-enabled，
        // 启用状态由 helper 在 root 身份下判定后回传。
        foreach (preg_split('/\r?\n/', $list['out']) as $line) {
            $line = rtrim($line);
            if ($line === '') continue;
            $parts = explode("\t", $line);
            $name  = $parts[0];
            $state = isset($parts[1]) ? $parts[1] : 'disabled';
            if (Helper::validateSiteName($name)) {
                $sites[] = [
                    'name'    => $name,
                    'enabled' => $state === 'enabled',
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
    if (!Helper::validateSiteName($name)) E::error('站点名无效');
    $r = Helper::run(['nginx-cat', $name]);
    if (!$r['ok']) E::error('读取失败：' . $r['out']);

    Tp::assign([
        'name'    => $name,
        'content' => $r['out'],
    ]);
    Tp::display();
});

Rout::put('save', function () {
    $name    = trim(ipost('name'));
    $content = ipost('content');
    if (!Helper::validateSiteName($name)) E::error('站点名无效');
    if (!is_string($content) || $content === '') E::error('内容为空');

    $r = Helper::run(['nginx-save', $name], $content);
    $r['ok'] ? E::success('已保存并重载') : E::error('nginx -t 失败：' . $r['out']);
});

Rout::put('reload', function () {
    $r = Helper::run(['nginx-reload']);
    $r['ok'] ? E::success('已重载') : E::error($r['out']);
});

Rout::put('test', function () {
    $r = Helper::run(['nginx-test']);
    $r['ok'] ? E::success($r['out'] ?: '语法 OK') : E::error($r['out']);
});

Rout::put('enable', function () {
    $name = trim(ipost('name'));
    if (!Helper::validateSiteName($name)) E::error('站点名无效');
    $r = Helper::run(['nginx-enable', $name]);
    $r['ok'] ? E::success('已启用：' . $name) : E::error($r['out']);
});

Rout::put('disable', function () {
    $name = trim(ipost('name'));
    if (!Helper::validateSiteName($name)) E::error('站点名无效');
    $r = Helper::run(['nginx-disable', $name]);
    $r['ok'] ? E::success('已停用：' . $name) : E::error($r['out']);
});
