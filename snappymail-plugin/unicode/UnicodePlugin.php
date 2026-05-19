<?php
/**
 * UNICODE webmail 品牌 + Cloudflare Turnstile + 关闭外发公告。
 *
 * 配置流向（详见 docs/UNICODE-WEBMAIL.md）：
 *   admin 面板「Webmail 品牌」页保存 →
 *   helper snappy-plugin-config-write 把数据落到：
 *     - config.json（PHP 端读，含 secret_key）
 *     - assets/config.js（JS 端读，site_key + outbound 标志，secret_key 不暴露）
 *   plugin Init() 加载 CSS/JS；login.js 读 window.UNICODE_CFG 渲染 widget / 公告。
 *   Login 提交时，server hook 拿 cf-turnstile-response 调 Cloudflare siteverify。
 */
class UnicodePlugin extends \RainLoop\Plugins\AbstractPlugin
{
    const NAME       = 'UNICODE';
    const VERSION    = '1.0.0';
    const RELEASE    = '2026-05-19';
    const REQUIRED   = '2.0.0';
    const CATEGORY   = 'General';
    const AUTHOR     = 'EwoMail-plus';
    const URL        = 'https://github.com/Null404-0/EwoMail-plus';
    const LICENSE    = 'MIT';
    const DESCRIPTION = 'UNICODE 品牌定制 + Cloudflare Turnstile 验证 + 关闭外发公告';

    /** in-process cache of config.json */
    private static $cfg = null;

    /** SnappyMail 某些版本要求 Init 有 :void 类型，加上更兼容 */
    public function Init() : void
    {
        // 同时加载 config.js（先）和 login.js（后）—— 顺序保证 login.js 读到
        // window.UNICODE_CFG。SnappyMail 按 add 顺序串到 <head>。
        $this->addCss('assets/login.css');
        $this->addJs('assets/config.js');
        $this->addJs('assets/login.js');

        // 登录前的人机验证拦截。SnappyMail 不同版本里 login 钩子名略有差异，
        // 同时挂多个常见 hook 名提高兼容性 —— 任何一个先触发都能拒绝登录。
        $this->addHook('login.credentials',        'BeforeLogin');
        $this->addHook('login.credentials.step-1', 'BeforeLogin');
        $this->addHook('login.credentials.step-2', 'BeforeLogin');

        // 修改密码 JSON 端点。同时挂多个 action 名，覆盖 SnappyMail 不同
        // 版本可能自动加的前缀（Do / Plugin），任一被 dispatcher 接走都能干活。
        // 不同 SnappyMail 版本里 addJsonHook 注册的 action 是否被 main
        // dispatcher 识别有差异，多挂几个保险。
        $this->addJsonHook('UnicodeChangePassword',        'doChangePassword');
        $this->addJsonHook('DoUnicodeChangePassword',      'doChangePassword');
        $this->addJsonHook('PluginUnicodeChangePassword',  'doChangePassword');

        // 调试用：把 Init 调用本身记到 PHP error log，确认 plugin 真的被
        // SnappyMail 加载了 + 这几个 hook 真的被注册了
        error_log('[UNICODE] Init done; CSS/JS added; login + UnicodeChangePassword hooks registered');
    }

    /** 读 plugin 目录下的 config.json，结果 in-memory 缓存。 */
    private static function cfg()
    {
        if (self::$cfg !== null) {
            return self::$cfg;
        }
        $file = __DIR__ . '/config.json';
        $cfg  = is_readable($file)
            ? json_decode((string) @file_get_contents($file), true)
            : null;
        self::$cfg = is_array($cfg) ? $cfg : [];
        return self::$cfg;
    }

    /** Hook entry：登录提交时调用。任一 hook 先到先验证，缓存防重复。 */
    private static $verified = false;
    public function BeforeLogin()
    {
        if (self::$verified) {
            return;
        }
        $cfg = self::cfg();
        if (($cfg['turnstile_enabled'] ?? 'no') !== 'yes') {
            self::$verified = true;
            return;
        }
        $secret = (string) ($cfg['turnstile_secret_key'] ?? '');
        if ($secret === '') {
            // 误配置（启用但没填 secret）—— 不能 fail-open 让攻击者绕过，
            // 直接报错让管理员去填。
            $this->fail('Turnstile 未配置 secret key，请联系管理员');
        }

        // SnappyMail 把请求字段塞进 $_POST。client 端 login.js 通过 fetch
        // 拦截把 cf-turnstile-response 注入到 form body 里。
        $token = isset($_POST['cf-turnstile-response'])
            ? (string) $_POST['cf-turnstile-response']
            : '';
        if ($token === '') {
            $this->fail('请先完成人机验证');
        }

        if (!$this->verifyTurnstile($secret, $token)) {
            $this->fail('人机验证失败，请重试');
        }
        self::$verified = true;
    }

    /** 抛 SnappyMail 通用客户端异常，前端会拿到 msg 文案。 */
    private function fail($msg)
    {
        $code = defined('\RainLoop\Notifications::AuthError')
            ? \RainLoop\Notifications::AuthError
            : 102;  // AuthError code in older versions
        throw new \RainLoop\Exceptions\ClientException($code, null, $msg);
    }

    /**
     * POST 到 Cloudflare siteverify。成功返回 true。失败 / 网络异常返回 false。
     * 故意保守：网络异常 → 拒登（不让攻击者通过断网绕过）。
     */
    private function verifyTurnstile($secret, $token)
    {
        $url = 'https://challenges.cloudflare.com/turnstile/v0/siteverify';
        $body = http_build_query([
            'secret'   => $secret,
            'response' => $token,
            // remoteip 可选，传上去 Cloudflare 会更智能
            'remoteip' => isset($_SERVER['REMOTE_ADDR']) ? $_SERVER['REMOTE_ADDR'] : '',
        ]);
        $ctx = stream_context_create([
            'http' => [
                'method'        => 'POST',
                'header'        => "Content-Type: application/x-www-form-urlencoded\r\n",
                'content'       => $body,
                'timeout'       => 5,
                'ignore_errors' => true,
            ],
            'ssl'  => ['verify_peer' => true, 'verify_peer_name' => true],
        ]);
        $resp = @file_get_contents($url, false, $ctx);
        if (!$resp) {
            return false;
        }
        $j = json_decode($resp, true);
        return is_array($j) && !empty($j['success']);
    }

    /**
     * 修改密码 JSON 端点。前端 login.js 通过 fetch 调到这里。
     *
     * SnappyMail 把 plugin 注册的 addJsonHook 路由进它的 Json action 体系，
     * 自动复用 session（要求用户已登录），且把方法返回值序列化成 JSON 响应。
     * 返回数组结构按 SnappyMail 习惯：{Result: ...} 或 {Error: ...}。
     *
     * 不让客户端传 email —— 直接从 SnappyMail 当前登录的 account 拿，防被
     * 越权改别人密码。
     */
    public function doChangePassword()
    {
        try {
            $oActions = \RainLoop\Api::Actions();
            $oAccount = null;
            // SnappyMail 不同版本拿当前账户的方法名不同，挨个试
            foreach (['getAccountFromToken', 'getMainAccountFromToken', 'GetAccount'] as $m) {
                if (method_exists($oActions, $m)) {
                    try { $oAccount = $oActions->$m(); } catch (\Throwable $e) { /* try next */ }
                    if ($oAccount) break;
                }
            }
            if (!$oAccount) {
                return ['Result' => ['success' => false, 'error' => '未登录或会话已过期，请重新登录']];
            }
            $email = method_exists($oAccount, 'Email') ? (string)$oAccount->Email() : '';
            if ($email === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
                return ['Result' => ['success' => false, 'error' => '无法获取当前用户邮箱']];
            }

            $oldPwd = isset($_POST['OldPassword']) ? (string)$_POST['OldPassword'] : '';
            $newPwd = isset($_POST['NewPassword']) ? (string)$_POST['NewPassword'] : '';

            if (strlen($newPwd) < 8 || strlen($newPwd) > 64) {
                return ['Result' => ['success' => false, 'error' => '新密码长度需 8-64 位']];
            }
            if ($oldPwd === '') {
                return ['Result' => ['success' => false, 'error' => '当前密码不能为空']];
            }
            if ($oldPwd === $newPwd) {
                return ['Result' => ['success' => false, 'error' => '新密码不能和当前密码相同']];
            }

            // 读 EwoMail 的 DB 配置 —— PHP-FPM 的 open_basedir 允许 /ewomail/www/
            $cfgFile = '/ewomail/www/ewomail-admin/core/config.php';
            if (!is_readable($cfgFile)) {
                return ['Result' => ['success' => false, 'error' => '服务器配置不可读']];
            }
            $cfg = @include $cfgFile;
            if (!is_array($cfg) || empty($cfg['dbhost']) || empty($cfg['dbname'])) {
                return ['Result' => ['success' => false, 'error' => '服务器 DB 配置异常']];
            }

            $pdo = new \PDO(
                "mysql:host={$cfg['dbhost']};dbname={$cfg['dbname']};charset=utf8mb4",
                (string)$cfg['dbuser'],
                (string)$cfg['dbpw'],
                [
                    \PDO::ATTR_ERRMODE => \PDO::ERRMODE_EXCEPTION,
                    \PDO::ATTR_EMULATE_PREPARES => false,
                ]
            );

            // 先确认账户在 i_users 里存在 —— 区分"账户不存在"和"密码错误"两种
            // 不同的失败，避免一律提示"密码错误"误导用户排错
            $stmt = $pdo->prepare("SELECT id, password FROM i_users WHERE email = ? LIMIT 1");
            $stmt->execute([$email]);
            $row = $stmt->fetch(\PDO::FETCH_ASSOC);
            if (!$row) {
                error_log('UNICODE pwchange: account not in i_users: ' . $email);
                return ['Result' => ['success' => false,
                    'error' => '账户 ' . $email . ' 不在 EwoMail 用户表里（可能是 webmail 自己的 admin 账号，不是邮箱用户）']];
            }

            // EwoMail 历史上密码就是 md5($password) 存的，没 salt。直接对比。
            // 同时也兼容理论上的 sha256/bcrypt 升级 —— 但先验 MD5 这条路径。
            $expectedMd5 = md5($oldPwd);
            if (strtolower((string)$row['password']) !== strtolower($expectedMd5)) {
                error_log(sprintf(
                    'UNICODE pwchange: password mismatch for %s (stored len=%d, expected MD5 len=%d)',
                    $email, strlen((string)$row['password']), strlen($expectedMd5)
                ));
                return ['Result' => ['success' => false,
                    'error' => '当前密码不正确（账户 ' . $email . '）']];
            }

            // 更新
            $stmt = $pdo->prepare("UPDATE i_users SET password = MD5(?) WHERE email = ?");
            $stmt->execute([$newPwd, $email]);
            if ($stmt->rowCount() < 1) {
                return ['Result' => ['success' => false,
                    'error' => '密码更新失败（rowCount=0），可能账户已被另一处会话修改']];
            }

            return ['Result' => ['success' => true, 'message' => '密码已修改，下次登录请使用新密码']];
        } catch (\PDOException $e) {
            error_log('UNICODE pwchange PDO error: ' . $e->getMessage());
            return ['Result' => ['success' => false, 'error' => '数据库错误：' . $e->getMessage()]];
        } catch (\Throwable $e) {
            error_log('UNICODE pwchange error: ' . $e->getMessage());
            return ['Result' => ['success' => false, 'error' => '服务器错误：' . $e->getMessage()]];
        }
    }
}
