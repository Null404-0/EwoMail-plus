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
 * 主程序运行
 */

if(!defined("PATH")) exit;
// 原版框架是 2016 年的代码，PHP 8.x 把许多原 Notice 提升成了 Warning
// （"Undefined array key" 等）。框架不会因这些 warning 出错，但 PHP-FPM
// 会把它们走 stderr 流回 nginx，海量噪音可能撑爆响应缓冲、把日志淹掉。
// 这里只保留 Error/Parse/Fatal 类，看到的就一定是真问题。
error_reporting(E_ERROR | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_USER_ERROR | E_RECOVERABLE_ERROR);
// 双重保险：万一 ini 没设住，运行时再关一次。
@ini_set('display_errors', 'Off');
header("Content-type: text/html; charset=utf-8");
include PATH.'/core/functions.php';
include PATH.'/lib/smarty-3.1.35/libs/Smarty.class.php';

//注册类
spl_autoload_register(function($class_name){
    static $class_arr;
    $dir_arr = [
        PATH.'/api/',
        PATH.'/core/class/',
    ];
    foreach($dir_arr as $key=>$value){
        if(!$class_arr[$class_name]){
            $file = $dir_arr[$key].$class_name.'.class.php';
            if(file_exists($file)){
                include $file;
                $class_arr[$class_name] = true;
                break;
            }
        }
    }
});

//url映射
Rout::core(function(){
    // When the admin panel is mounted under /<admin_path>/ (EwoMail-plus default),
    // PHP-FPM hands us PATH_INFO already stripped of both the base path and the
    // index.php segment, so prefer that. Fall back to the legacy DOCUMENT_URI
    // logic for backwards compatibility with the original deployment shape.
    if(!empty($_SERVER['PATH_INFO']) && $_SERVER['PATH_INFO'] !== '/'){
        $_SERVER['REDIRECT_URL'] = $_SERVER['PATH_INFO'];
    }else if(isset($_SERVER['DOCUMENT_URI'])){
        $DOCUMENT_URI = trim($_SERVER['DOCUMENT_URI'],'/');
        $paths = explode('/',$DOCUMENT_URI);
        // Strip leading base-path segment if it matches the configured admin_path,
        // then drop the index.php segment as the original code did.
        $base = trim((string)C('admin_path'), '/');
        if($base !== '' && isset($paths[0]) && $paths[0] === $base){
            array_shift($paths);
        }
        if(isset($paths[0]) && $paths[0] === 'index.php'){
            array_shift($paths);
        }
        $_SERVER['REDIRECT_URL'] = '/'.implode("/",$paths);
        $paths = null;
    }
    //apache
    if(isset($_SERVER['REDIRECT_URL'])){
        $REDIRECT_URL = trim($_SERVER['REDIRECT_URL'],'/');
        $paths = explode('/',$REDIRECT_URL);
        if(count($paths)<3){
            if($paths[0]!=C('home_default') && !in_array($paths[0],C('home_allow'))){
                array_unshift($paths,C('home_default'));
            }
        }
        $home = $paths[0];
        $module = $paths[1]?$paths[1]:C('module_default');
        $action = $paths[2]?$paths[2]:C('action_default');
    }else{
        $home = C('home_default');
        $module = C('module_default');
        $action = C('action_default');
    }
    
    define("HOME",$home);//当前模块
    define("MODULE",$module);//当前控制器
    define("ACTION",$action);//当前动作
    if(!in_array(HOME,C('home_allow'))){
        E::sys($home.'模块不存在');
    }
    define('REQUEST_METHOD',$_SERVER['REQUEST_METHOD']);
    define('IS_GET',        REQUEST_METHOD =='GET' ? true : false);
    define('IS_POST',       REQUEST_METHOD =='POST' ? true : false);
    define('IS_AJAX',       ((isset($_SERVER['HTTP_X_REQUESTED_WITH']) && strtolower($_SERVER['HTTP_X_REQUESTED_WITH']) == 'xmlhttprequest')) ? true : false);
});


//初始化
Rout::core(function(){
    $session_id = iget('session_id')?iget('session_id'):ipost('session_id');
    if($session_id){
        session_id($session_id);
    }
    session_start();
    
    Tp::init();
    $file = PATH.'/module/'.HOME.'/'.MODULE.'.php';
    $initFile = PATH.'/module/'.HOME.'/'.'_init.php';
    
    if(file_exists($initFile)){
        include $initFile;
    }else{
        E::sys(HOME.'模块的_init文件不存在');
    }
    if(file_exists($file)){
        include $file;
    }else{
        E::sys(MODULE.'控制器不存在');
    }
    
});

Rout::run();

