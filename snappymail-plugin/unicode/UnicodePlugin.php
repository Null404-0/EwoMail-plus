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
        // 第二个参数 false = 所有页面都加（不只是登录页）—— 我们需要在用户
        // 登录后的 UI 里也跑 sweep（隐藏主题入口、不可见文件夹、抑制弹窗）。
        $this->addCss('assets/login.css');
        $this->addJs('assets/config.js');
        $this->addJs('assets/login.js');

        // 登录前的人机验证拦截。SnappyMail 不同版本里 login 钩子名略有差异，
        // 同时挂多个常见 hook 名提高兼容性 —— 任何一个先触发都能拒绝登录。
        // 触发后实际验证只跑一次（self::$verified 缓存），不会重复打 LE。
        $this->addHook('login.credentials',        'BeforeLogin');
        $this->addHook('login.credentials.step-1', 'BeforeLogin');
        $this->addHook('login.credentials.step-2', 'BeforeLogin');
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
}
