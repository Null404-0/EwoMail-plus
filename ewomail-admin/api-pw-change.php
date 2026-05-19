<?php
/**
 * 独立的密码修改端点。
 *
 * 不走 SnappyMail 的 plugin Ajax 系统（实测它的 addJsonHook 在 2.38
 * 上拒绝注册新 action），也不走 EwoMail 管理后台的 admin auth。直接
 * 通过 nginx 路由到这里：location = /api-pw-change → fastcgi → 本文件。
 *
 * 安全模型：要求请求者提供 email + 当前密码 + 新密码。验证 (email,
 * old) 命中 i_users 才允许 UPDATE。门槛和"登录 webmail"完全等价，
 * 没有降低安全性。配合 fail2ban 限流防暴破。
 */

header('Content-Type: application/json; charset=utf-8');
header('X-Content-Type-Options: nosniff');
header('Cache-Control: no-store');

function _reply(array $a, int $status = 200): void {
    http_response_code($status);
    echo json_encode($a, JSON_UNESCAPED_UNICODE);
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    _reply(['success' => false, 'error' => 'POST only'], 405);
}

$email = trim((string)($_POST['email'] ?? ''));
$old   = (string)($_POST['old']   ?? '');
$new   = (string)($_POST['new']   ?? '');

if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    _reply(['success' => false, 'error' => '邮箱格式无效']);
}
if ($old === '') {
    _reply(['success' => false, 'error' => '当前密码不能为空']);
}
if (strlen($new) < 8 || strlen($new) > 64) {
    _reply(['success' => false, 'error' => '新密码需 8-64 位']);
}
if ($old === $new) {
    _reply(['success' => false, 'error' => '新密码不能和当前密码相同']);
}

$cfg = @include __DIR__ . '/core/config.php';
if (!is_array($cfg) || empty($cfg['dbhost']) || empty($cfg['dbname'])) {
    error_log('[UNICODE-PW] config.php load failed');
    _reply(['success' => false, 'error' => '服务器配置错误'], 500);
}

try {
    $pdo = new PDO(
        "mysql:host={$cfg['dbhost']};dbname={$cfg['dbname']};charset=utf8mb4",
        (string)$cfg['dbuser'],
        (string)$cfg['dbpw'],
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]
    );

    $stmt = $pdo->prepare("SELECT id FROM i_users WHERE email = ? AND password = MD5(?) LIMIT 1");
    $stmt->execute([$email, $old]);
    if (!$stmt->fetchColumn()) {
        // 故意不区分"邮箱不存在"和"密码错误" —— 避免枚举攻击
        // 加一点点延迟降低 timing attack 威力
        usleep(300000);  // 0.3s
        _reply(['success' => false, 'error' => '邮箱或当前密码错误']);
    }

    $stmt = $pdo->prepare("UPDATE i_users SET password = MD5(?) WHERE email = ?");
    $stmt->execute([$new, $email]);
    if ($stmt->rowCount() < 1) {
        _reply(['success' => false, 'error' => '密码更新失败']);
    }

    _reply(['success' => true, 'message' => '密码已修改，下次登录请使用新密码']);
} catch (Throwable $e) {
    error_log('[UNICODE-PW] ' . $e->getMessage() . ' at ' . $e->getFile() . ':' . $e->getLine());
    _reply(['success' => false, 'error' => '服务器错误'], 500);
}
