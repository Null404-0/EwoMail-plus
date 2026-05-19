<?php
/**
 * SnappyMail plugin loader.
 *
 * SnappyMail 的 plugin 发现机制：扫 plugins 目录的 index.php，文件需要
 * `return $instance` —— 返回一个继承 \RainLoop\Plugins\AbstractPlugin
 * 的对象实例。这里把实现类拆到 UnicodePlugin.php 方便编辑器跳转。
 */
require_once __DIR__ . '/UnicodePlugin.php';

return new UnicodePlugin();
