<?php
// +----------------------------------------------------------------------
// | EwoMail
// +----------------------------------------------------------------------
// | Copyright (c) 2016 http://ewomail.com All rights reserved.
// +----------------------------------------------------------------------
// | Licensed ( http://ewomail.com/license.html)
// +----------------------------------------------------------------------
// | Author: Jun <gyxuehu@163.com>
// +----------------------------------------------------------------------
/**
 * 系统设置
 */
if(!defined("PATH")) exit;

Rout::get('index',function(){
    Admin::setMenu(0,L(3053));
    $os = explode(" ", php_uname());
    //mysql版本
    $mysql_version = App::$db->getOne("select VERSION()");
    $domain_count = App::$db->count("select count(*) from ".table("domains"));
    $users_count = App::$db->count("select count(*) from ".table("users"));
    $bytes_count = App::$db->count("select sum(bytes) from ".table("quota"));
    $bytes_count = byteFormat($bytes_count,'GB');

    $default_password = false;
    if(Admin::$info['username']=='admin' && Admin::$info['password']==md5('ewomail123')){
        $default_password = true;
    }
    

    $arr = [
        'php'=>PHP_VERSION,
        'web'=>$_SERVER['SERVER_SOFTWARE'],
        'ip'=>$_SERVER['SERVER_ADDR'],
        'upload_max_filesize'=>get_cfg_var('upload_max_filesize'),
        'post_max_size'=>get_cfg_var('post_max_size'),
        'uname'=>$os[0],
        'hostname'=>$os[2],
        'mysql'=>$mysql_version['version()'],
        'version'=>App::$version,
        'users_count'=>$users_count,
        'domain_count'=>$domain_count,
        'bytes_count'=>$bytes_count
    ];
    
    
    //操作日志
    $log_list = App::$db->select("select * from ".table("admin_log")." order by ctime desc limit 0,10");

    $newArr = [
        'data'=>$arr,
        'log_list'=>$log_list,
        'default_password'=>$default_password
    ];
    Tp::assign($newArr);
    Tp::display();
});

//退出
Rout::get('out',function(){
    Session::clear();
    header("Location:".U('/Index/login'));
    exit;
});

//系统配置
Rout::get('config',function(){
    Admin::setMenu(205);
    $systemConfig = new SystemConfig();
    $data = $systemConfig->getAll();
    
    $arr = [
        'langData'=>SystemConfig::getLang(),
        'data'=>$data
    ];
    
    Tp::assign($arr);
    Tp::display();
});

Rout::put('config',function(){
    Admin::setMenu(205);
    $data = ipost('data');
    $systemConfig = new SystemConfig();
    $systemConfig->save($data);
    E::success(1001);
});

// SnappyMail（Webmail）品牌设置：直接读写 application.ini
Rout::get('webmail-config', function () {
    Admin::setMenu(207, 'Webmail 品牌');
    Tp::assign(['snappy' => SystemConfig::snappyIniRead()]);
    Tp::display();
});

Rout::put('webmail-config', function () {
    $updates = [
        'title'               => trim((string) ipost('title')),
        'loading_description' => trim((string) ipost('loading_description')),
    ];
    if (isset($_FILES['favicon']) && $_FILES['favicon']['error'] !== UPLOAD_ERR_NO_FILE) {
        if ($_FILES['favicon']['error'] !== UPLOAD_ERR_OK) {
            E::error('文件上传出错（错误码 ' . intval($_FILES['favicon']['error']) . '）');
        }
        $updates['favicon_url'] = SystemConfig::snappyFaviconSave($_FILES['favicon']);
    } elseif (ipost('favicon_clear') === '1') {
        SystemConfig::snappyFaviconClear();
        $updates['favicon_url'] = '';
    }
    SystemConfig::snappyIniWrite($updates);
    AdminLog::save(['ac' => 'edit', 'c' => 'Webmail 品牌']);
    E::success('已保存（Webmail 下次刷新即生效）');
});





Rout::get('turnstile-config', function () {
    Admin::setMenu(208, 'Turnstile 设置');
    Tp::assign(['data' => [
        'turnstile_enabled' => Helper::setting('turnstile_enabled', '0'),
        'turnstile_site_key' => Helper::setting('turnstile_site_key', ''),
        'turnstile_secret_key' => Helper::setting('turnstile_secret_key', '')
    ]]);
    Tp::display();
});

Rout::put('turnstile-config', function () {
    $enabled = ipost('turnstile_enabled') === '1' ? '1' : '0';
    $siteKey = trim((string)ipost('turnstile_site_key'));
    $secret = trim((string)ipost('turnstile_secret_key'));
    Helper::settingSet('turnstile_enabled', $enabled);
    Helper::settingSet('turnstile_site_key', $siteKey);
    Helper::settingSet('turnstile_secret_key', $secret);

    $payload = json_encode([
        'turnstile_enabled' => $enabled,
        'turnstile_site_key' => $siteKey,
        'turnstile_secret_key' => $secret,
        'outbound_disabled' => Helper::setting('outbound_disabled', 'no')
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    $r = Helper::run(['snappy-turnstile-write'], $payload . "
");
    if (!$r['ok']) {
        E::error('写入 SnappyMail 插件配置失败：' . $r['out']);
    }
    AdminLog::save(['ac' => 'edit', 'c' => 'Turnstile 设置']);
    E::success('已保存');
});

