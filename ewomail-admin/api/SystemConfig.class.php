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
 * 系统配置类
 * Class SystemConfig
 */
class SystemConfig extends App
{
    /**
     * 获取一条数据
     * @param $name
     * @return mixed
     */
    public static function get($name)
    {
        $row = App::$db->getOne("select value from ".table("system_config")." where name='$name'");
        return $row['value'];
    }

    /**
     * 获取当前配置语言
     * @return array|mixed
     */
    public static function getLang()
    {
        static $r = [];
        if(!$r){
            $r = include PATH.'/lang/config.php';
        }
        return $r;
    }

    /**
     * 保存数据
     * @param $data
     */
    public function save($data)
    {
        foreach($data as $k=>$v){
            $newData = [
                'value'=>$v
            ];
            App::$db->update('system_config',$newData,"name='$k'");
        }
        $logData = [
            'ac'=>'edit',
            'c'=>'系统设置'
        ];
        AdminLog::save($logData);
    }

    /**
     * 获取全部数据
     * @return array
     */
    public function getAll()
    {
        $data = App::$db->select("select * from ".table("system_config"));
        $newData = [];
        foreach($data as $v){
            $newData[$v['name']] = $v['value'];
        }
        return $newData;
    }

    /* -----------------------------------------------------------------
     *  SnappyMail (Webmail) 品牌设置
     *  -----------------------------------------------------------------
     *  关键 ini 字段全在 [webmail] 段：
     *    title                浏览器标签 / 页面标题
     *    loading_description  载入页文字
     *    favicon_url          自定义 favicon 的 URL 路径
     *
     *  这些方法以 line-based 形式读写 ini，保留注释与未涉及的字段。
     * ----------------------------------------------------------------- */
    const SNAPPY_INI    = '/ewomail/www/snappymail/data/_data_/_default_/configs/application.ini';
    const SNAPPY_ROOT   = '/ewomail/www/snappymail';
    const FAVICON_DIR   = '/ewomail/www/snappymail/branding';

    public static function snappyIniRead()
    {
        $out = ['title' => '', 'loading_description' => '', 'favicon_url' => ''];
        if (!is_readable(self::SNAPPY_INI)) return $out;
        $current = '';
        foreach (file(self::SNAPPY_INI) as $line) {
            $t = ltrim($line);
            if ($t === '' || $t[0] === ';') continue;
            if (preg_match('/^\[([a-zA-Z0-9_]+)\]/', $t, $m)) { $current = $m[1]; continue; }
            if ($current !== 'webmail') continue;
            if (preg_match('/^([a-zA-Z0-9_]+)\s*=\s*(.*)$/', $t, $m)) {
                $key = $m[1];
                if (!isset($out[$key])) continue;
                $val = trim($m[2]);
                if (strlen($val) >= 2 && $val[0] === '"' && substr($val, -1) === '"') {
                    $val = stripcslashes(substr($val, 1, -1));
                }
                $out[$key] = $val;
            }
        }
        return $out;
    }

    /**
     * 把给定 key=>val 写回 [webmail] 段。保留注释 / 其他键。
     * 不存在的键会附加到段末尾。
     */
    public static function snappyIniWrite(array $updates)
    {
        if (!is_writable(self::SNAPPY_INI)) {
            E::error('无法写入 ' . self::SNAPPY_INI . '（检查权限）。');
        }
        $lines     = file(self::SNAPPY_INI);
        $current   = '';
        $applied   = [];
        $sectStart = -1;
        $sectEnd   = -1;
        foreach ($lines as $i => $line) {
            $t = ltrim($line);
            if (preg_match('/^\[([a-zA-Z0-9_]+)\]/', $t, $m)) {
                if ($current === 'webmail' && $sectEnd === -1) $sectEnd = $i;
                $current = $m[1];
                if ($current === 'webmail') $sectStart = $i;
                continue;
            }
            if ($current !== 'webmail') continue;
            if (preg_match('/^([a-zA-Z0-9_]+)\s*=\s*(.*)$/', $t, $m)) {
                $key = $m[1];
                if (!array_key_exists($key, $updates)) continue;
                $esc = '"' . addcslashes($updates[$key], "\"\\") . '"';
                $lines[$i] = $key . ' = ' . $esc . "\n";
                $applied[$key] = true;
            }
        }
        if ($current === 'webmail' && $sectEnd === -1) $sectEnd = count($lines);

        // 处理未存在的键：追加到 [webmail] 段末尾
        $missing = array_diff_key($updates, $applied);
        if ($missing && $sectStart >= 0) {
            $insert = [];
            foreach ($missing as $k => $v) {
                $esc = '"' . addcslashes($v, "\"\\") . '"';
                $insert[] = $k . ' = ' . $esc . "\n";
            }
            array_splice($lines, $sectEnd, 0, $insert);
        }

        if (file_put_contents(self::SNAPPY_INI, implode('', $lines)) === false) {
            E::error('写入 application.ini 失败');
        }
    }

    /**
     * 校验并保存上传的 favicon 文件，返回 web 可访问 URL。
     * 允许: ico / png / jpg / gif，<= 256 KB。SVG 不接受（XSS 风险）。
     */
    public static function snappyFaviconSave(array $upload)
    {
        if (!isset($upload['tmp_name']) || !is_uploaded_file($upload['tmp_name'])) {
            E::error('未收到上传文件');
        }
        if ($upload['size'] > 256 * 1024) {
            E::error('文件过大（上限 256 KB）');
        }
        $type = function_exists('mime_content_type') ? mime_content_type($upload['tmp_name']) : '';
        $extMap = [
            'image/x-icon'    => 'ico',
            'image/vnd.microsoft.icon' => 'ico',
            'image/png'       => 'png',
            'image/jpeg'      => 'jpg',
            'image/gif'       => 'gif',
        ];
        if (!isset($extMap[$type])) {
            E::error('不支持的文件类型：' . ($type ?: 'unknown') . '（允许 .ico / .png / .jpg / .gif）');
        }
        $ext = $extMap[$type];
        if (!is_dir(self::FAVICON_DIR)) {
            if (!mkdir(self::FAVICON_DIR, 0755, true)) {
                E::error('无法创建 ' . self::FAVICON_DIR);
            }
        }
        // 清掉旧的 favicon.* 文件（用户可能换了扩展名）
        foreach (glob(self::FAVICON_DIR . '/favicon.*') as $old) @unlink($old);
        $dest = self::FAVICON_DIR . '/favicon.' . $ext;
        if (!move_uploaded_file($upload['tmp_name'], $dest)) {
            E::error('保存上传文件失败');
        }
        @chmod($dest, 0644);
        return '/branding/favicon.' . $ext;
    }

    public static function snappyFaviconClear()
    {
        foreach (glob(self::FAVICON_DIR . '/favicon.*') as $old) @unlink($old);
    }
}