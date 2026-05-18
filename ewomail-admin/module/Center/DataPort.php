<?php
/**
 * DataPort: 邮箱数据的导入 / 导出。
 *
 * 导出：通过 helper 调 mysqldump 导出邮件业务表（i_users/i_domains/i_aliases/
 *       i_bcc_user/i_quota[/i_day_record]）为纯 INSERT 的 SQL，下载到本地。
 *
 * 导入：上传任意 mysqldump 风格的 SQL 文件（新版 EwoMail-plus 自身导出的，
 *       或老版 EwoMail 的 mysqldump），helper 端做白名单过滤 + INSERT IGNORE
 *       重写，admin/menu/system_config 等表完全忽略，只挑业务表的 INSERT。
 *
 * 旧版兼容：i_users/i_domains/i_aliases/i_bcc_user/i_quota 的列结构在新旧版
 * 完全一致（详见 ewomail-admin/upload/install.sql），所以这条迁移路径就是
 * 「上传 → 导入」一步搞定。新版多出来的 i_panel_setting 表不需要从旧版导入。
 */
if (!defined('PATH')) exit;

const _IMPORT_TABLES = ['i_users', 'i_domains', 'i_aliases', 'i_bcc_user', 'i_quota', 'i_day_record'];
const _IMPORT_MAX    = 32 * 1024 * 1024;  // 32 MB —— 邮件元数据再多也不会撑爆

Rout::get('index', function () {
    Admin::setMenu(106, '数据导入/导出');

    // i_day_record 不在 install.sql 里，老 EwoMail 也只在某些组件首次写入时
    // 才会自动建。所以全新装的 EwoMail-plus 上这张表可能不存在；不能盲目
    // count，否则 PDO 抛 Table doesn't exist 一路冒泡到 E::sys 整页 500。
    $existing = [];
    $rows = App::$db->select(
        "select TABLE_NAME from INFORMATION_SCHEMA.TABLES " .
        "where TABLE_SCHEMA = DATABASE() and TABLE_NAME in ('" .
        implode("','", _IMPORT_TABLES) . "')"
    );
    if (is_array($rows)) {
        foreach ($rows as $r) {
            // PDO 配了 ATTR_CASE = CASE_LOWER，列名是小写
            $name = isset($r['table_name']) ? $r['table_name'] : null;
            if ($name) $existing[$name] = true;
        }
    }

    $stats = [];
    foreach (_IMPORT_TABLES as $t) {
        $stats[$t] = isset($existing[$t])
            ? (int)App::$db->count("select count(*) from `" . $t . "`")
            : null;  // null = 表不存在，模板里显示 "—"
    }
    Tp::assign(['stats' => $stats]);
    Tp::display();
});

/** 导出：让浏览器下载 SQL 文件 */
Rout::get('export', function () {
    $r = Helper::run(['db-export']);
    if (!$r['ok']) {
        E::sys('导出失败：' . $r['out']);
    }
    $filename = 'ewomail-export-' . date('Ymd-His') . '.sql';
    header('Content-Type: application/sql; charset=utf-8');
    header('Content-Disposition: attachment; filename="' . $filename . '"');
    header('Content-Length: ' . strlen($r['out']));
    header('X-Content-Type-Options: nosniff');
    echo "-- EwoMail-plus 导出\n";
    echo "-- 时间: " . date('c') . "\n";
    echo "-- 表: " . implode(', ', _IMPORT_TABLES) . "\n";
    echo "-- 仅含 INSERT 语句，schema 由 install.sql 创建。\n\n";
    echo $r['out'];
    exit;  // 必须 exit，避免框架后续输出污染响应体
});

/** 导入：接收 multipart 上传 → helper 过滤+应用 → 返回每表行数 */
Rout::put('import', function () {
    if (empty($_FILES['sqlfile']) || !is_uploaded_file($_FILES['sqlfile']['tmp_name'])) {
        E::error('没有收到上传文件');
    }
    $err = $_FILES['sqlfile']['error'];
    if ($err !== UPLOAD_ERR_OK) {
        E::error('文件上传失败（错误码 ' . $err . '）');
    }
    if ($_FILES['sqlfile']['size'] > _IMPORT_MAX) {
        E::error('文件超过 ' . (_IMPORT_MAX / 1024 / 1024) . ' MB 上限');
    }
    $sql = file_get_contents($_FILES['sqlfile']['tmp_name']);
    if ($sql === false || $sql === '') {
        E::error('文件为空或无法读取');
    }
    // 粗略字符串检查：必须看起来像 SQL
    if (!preg_match('/INSERT\s+(IGNORE\s+)?INTO/i', $sql)) {
        E::error('文件中没有找到任何 INSERT 语句，请确认是 mysqldump 输出');
    }

    $r = Helper::run(['db-import'], $sql);
    if (!$r['ok']) {
        E::error('导入失败：' . ($r['out'] ?: '未知错误'));
    }

    // 解析 helper 输出："table=i_users count=42\ntable=i_domains count=3\napplied=ok"
    $per_table = [];
    foreach (preg_split('/\R/', $r['out']) as $line) {
        if (preg_match('/^table=([a-z_]+)\s+count=(\d+)/', $line, $m)) {
            $per_table[$m[1]] = (int)$m[2];
        }
    }

    AdminLog::save(['ac' => 'add', 'c' => '导入 SQL：' . json_encode($per_table, JSON_UNESCAPED_UNICODE)]);
    E::success('导入完成', '', $per_table);
});
