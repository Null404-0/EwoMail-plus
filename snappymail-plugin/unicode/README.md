# UNICODE Webmail Plugin

EwoMail-plus 的 SnappyMail 品牌定制 plugin。装机和升级时自动落到
`/ewomail/www/snappymail/data/_data_/_default_/plugins/unicode/`，并在
SnappyMail 的 `application.ini` 里启用。**不需要也不应该手动改这里的文件**
—— 所有配置都从管理后台「系统管理 → Webmail 品牌」页推下来。

## 功能

- 登录页红黑品牌主题 + UNICODE logo + 标语
- Cloudflare Turnstile 人机验证（可在后台开关）
- 后台关闭外发邮件时登录页顶部弹红色公告
- 隐藏 SnappyMail 用户端的主题切换入口
- 抑制每次登录后的欢迎 / onboarding 弹窗

## 配置 Cloudflare Turnstile

1. 注册 Cloudflare 账号（免费，**不需要把域名托管在 CF**）：
   <https://dash.cloudflare.com/>
2. 左侧菜单进 **Turnstile** → **Add Site**
3. 填表：
   - **Site Name**：随意，例如 `unicode-mail`
   - **Domain**：你的邮件主机名（如 `mail.unicode.xxx`），不带 `https://`
     **必须填实际访问 webmail 用的域名**，否则 widget 报"domain mismatch"
   - **Widget Mode**：选 **Managed**（推荐，绝大部分用户无感）
4. 创建完拿到两把 key：
   - **Site Key**（公开，pk_ 开头）
   - **Secret Key**（私密，sk_ 开头，别外泄）
5. 进 EwoMail 管理后台 → 系统管理 → Webmail 品牌
   - 把"启用 Turnstile"切到开
   - 粘贴 Site Key + Secret Key
   - 保存

后端会同时验证：JS 端没解出 token 就锁登录按钮（UX 反馈），
即便 JS 被绕过，PHP 端 hook 也会拒登。

## 文件清单

| 文件 | 干啥 |
|---|---|
| `index.php` | SnappyMail plugin 入口，返回 UnicodePlugin 实例 |
| `UnicodePlugin.php` | 主类：注册 CSS/JS + 登录前 Turnstile siteverify |
| `assets/login.css` | 登录页 + 用户设置页的红黑主题样式 |
| `assets/login.js` | logo / banner 注入 + Turnstile widget + fetch 拦截 |
| `assets/logo.svg` | 占位 logo（待替换为 PNG） |
| `assets/config.js` | **由 helper 生成**：暴露 site_key / outbound 状态给 JS |
| `config.json` | **由 helper 生成**：暴露 secret_key 给 PHP；JS 看不到 |

## 数据流

```
[Admin 面板 "Webmail 品牌" 页]
    保存 → i_panel_setting（数据库 source of truth）
                   ↓
            Helper::run(['snappy-plugin-config-write','unicode'], JSON)
                   ↓
[plugin 目录]
    config.json        (PHP 端读：secret_key + enabled)
    assets/config.js   (JS 端读：site_key + outbound 标志)

[用户访问 webmail 登录页]
    Browser 加载 plugin assets
    login.js 看到 window.UNICODE_CFG.turnstile_enabled=='yes'
        → loadTurnstileApi() → turnstile.render(...) → 用户解
        → callback 拿到 token，按钮解锁
    用户点登录
        → SnappyMail 发 AJAX 到 /?/Ajax/...
        → 我们 monkey-patch 的 fetch / XHR.send 把 cf-turnstile-response
           塞进 body
        → server UnicodePlugin::BeforeLogin hook 触发
        → POST 到 challenges.cloudflare.com/turnstile/v0/siteverify
        → success=true 放行；否则抛 ClientException
```
