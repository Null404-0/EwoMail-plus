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

    // 当前运行的 nginx 版本（裸数字）+ 是否来自 nginx.org（用于在 UI 标注）
    $ver = Helper::run(['nginx-version']);
    $nginx_version  = $ver['ok'] ? trim($ver['out']) : '未知';
    // 简单判断：1.22.x 是 Debian 12 自带、1.30+ 一般来自 nginx.org stable
    $is_debian_stock = (bool)preg_match('/^1\.(22|18|14)\./', $nginx_version);

    Tp::assign([
        'sites'           => $sites,
        'test_out'        => $test['out'],
        'test_ok'         => $test['ok'],
        'nginx_version'   => $nginx_version,
        'is_debian_stock' => $is_debian_stock,
    ]);
    Tp::display();
});

Rout::put('upgrade', function () {
    // 升级动作较重（apt-get update + install + reload），可能耗时 1-3 分钟。
    // 前端 ajax timeout 必须给够，否则会断给用户假超时（参考 Cert 模块的
    // pLong helper）。
    $r = Helper::run(['nginx-upgrade']);
    // 把 helper 输出按行拆开，前端展示 step= 和 version= 等关键字段；
    // 但完整输出（含 apt 进度）也透传过去，方便排查。
    $info = ['output' => $r['out']];
    foreach (preg_split('/\R/', $r['out']) as $line) {
        if (preg_match('/^(step|backup|version|note)=(.+)$/', $line, $m)) {
            $info[$m[1]] = $m[2];
        }
    }
    if (!$r['ok']) {
        E::error('升级失败（rc=' . $r['rc'] . '）：' . substr($r['out'], -800), '', $info);
    }
    AdminLog::save(['ac' => 'edit', 'c' => 'Nginx 升级到 ' . ($info['version'] ?? '?')]);
    E::success('升级完成，当前版本：' . ($info['version'] ?? '?'), '', $info);
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
