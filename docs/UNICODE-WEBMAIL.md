# UNICODE Webmail 改造方案

## 1) 目录结构（SnappyMail Plugin）

计划新增 `snappymail-plugin/unicode/`：

- `index.php`：SnappyMail plugin 入口，注册插件类。
- `UnicodePlugin.php`：核心逻辑（读取配置、注入 CSS/JS、登录校验 hook）。
- `assets/`
  - `logo.svg`：占位 logo（TODO: 后续替换为 logo.png）。
  - `unicode.css`：登录页品牌样式、公告横幅、按钮主题。
  - `unicode.js`：Turnstile widget 渲染、欢迎弹窗隐藏、主题入口隐藏。
- `README.md`：Cloudflare Turnstile 配置指引。
- `config.json`：运行时配置（由后台 + helper 写入部署目录 data 插件目录）。

## 2) 后台/Helper/Plugin 数据流

```text
[Admin 系统设置页面 /System/turnstile-config]
            |
            | PUT turnstile_enabled/site_key/secret_key
            v
 [i_panel_setting] <---- 同步读取 outbound_disabled ----
            |
            | Helper::run(['snappy-turnstile-write', JSON])
            v
/ewomail/www/snappymail/data/_data_/_default_/plugins/unicode/config.json
            |
            +--> plugin 登录渲染阶段读取: 品牌、开关、site key、公告状态
            |
            +--> plugin 登录提交校验阶段读取: secret key + cf-turnstile-response
                    -> POST https://challenges.cloudflare.com/turnstile/v0/siteverify
                    -> success=true 允许登录；否则返回中文错误
```

## 3) 计划使用的 SnappyMail Plugin Hook

- `Init` / 初始化注册：加载配置与公共资源。
- `Login render`（登录页面渲染阶段）：
  - 注入品牌 CSS/JS；
  - 在密码框与登录按钮之间插入 Turnstile 容器；
  - 根据 `outbound_disabled` 展示公告；
  - 注入 logo + UNICODE 文案。
- `Login attempt / authenticate`（登录提交认证阶段）：
  - 读取 `cf-turnstile-response`；
  - 服务端调用 Turnstile `siteverify`；
  - 失败中止登录并返回中文友好错误。

> 注：具体 hook 名称会按 SnappyMail 版本实际 API 常量/方法微调。

## 4) 变更归属

### 后台改动（ewomail-admin）

- `module/Center/System.php`：新增 `turnstile-config` GET/PUT 路由。
- `templates/Center/System/turnstile-config.html`：新增配置页。
- `core/class/Helper.class.php`：`settingAllowed()` 白名单添加三个 turnstile key。
- 菜单初始化与升级脚本：新增 menu_id=208。

### helper 改动

- `install/templates/admin-helper/ewomail-helper`：新增 `snappy-turnstile-write` 子命令。
  - 输入：JSON（stdin）
  - 输出：写入 `.../plugins/unicode/config.json`
  - 权限：`root:www-data` + `0640`

### plugin 改动

- `snappymail-plugin/unicode/*`：实现品牌样式、Turnstile 挂载与验证、公告、禁主题、去欢迎弹窗。

### 安装/升级改动

- `install/lib/webapps.sh`：装机时拷贝 plugin 到 snappymail data plugins 目录并启用。
- `update.sh`：升级时同步拷贝 plugin，补齐菜单项。

