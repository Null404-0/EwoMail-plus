/*
 * UNICODE webmail login customisation.
 *
 * 负责的事：
 *   1. 在登录卡片上方注入品牌 logo + 标语
 *   2. 当 outbound 被关闭时注入"已关闭发信"红色横幅
 *   3. 渲染 Cloudflare Turnstile widget 并把 token 塞进登录请求
 *   4. 解除每次登录后弹出的"欢迎/onboarding" 弹窗（如果有）
 *
 * 读 window.UNICODE_CFG（由 assets/config.js 注入，由 helper 端写出）。
 * SnappyMail 用 Knockout/Vue 异步渲染登录表单，所以这里全靠
 * MutationObserver + 轮询找元素。
 */
(function () {
    'use strict';

    var CFG = window.UNICODE_CFG || {};
    var TURNSTILE_ENABLED = (CFG.turnstile_enabled === 'yes');
    var TURNSTILE_SITE_KEY = (CFG.turnstile_site_key || '');
    var OUTBOUND_DISABLED = (CFG.outbound_disabled === 'yes');

    var turnstileToken = '';      // 最近一次 Turnstile 解出的 token
    var widgetRendered = false;

    // ---------- Brand + Banner DOM 注入 ----------

    function loginFormEl() {
        return document.querySelector('.b-login-form, .login-form, #rl-app form');
    }

    function injectBrand() {
        if (document.querySelector('.unicode-brand')) return true;
        var form = loginFormEl();
        if (!form) return false;
        var brand = document.createElement('div');
        brand.className = 'unicode-brand';
        brand.innerHTML =
            '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg" aria-label="UNICODE">' +
              '<defs><linearGradient id="ug" x1="0" y1="0" x2="1" y2="1">' +
                '<stop offset="0%" stop-color="#dc143c"/>' +
                '<stop offset="100%" stop-color="#8b0000"/>' +
              '</linearGradient></defs>' +
              '<circle cx="32" cy="32" r="28" fill="none" stroke="url(#ug)" stroke-width="2"/>' +
              '<path d="M22 22h4v18a6 6 0 0 0 12 0V22h4v18a10 10 0 0 1-20 0z" fill="url(#ug)"/>' +
            '</svg>' +
            '<div class="name">UNICODE</div>' +
            '<div class="slogan">SECURE · FAST · LIMITLESS</div>' +
            '<div class="slogan-cn">代码无界 未来无限</div>';
        // 插到 form 第一个 child 前面
        form.insertBefore(brand, form.firstChild);
        return true;
    }

    function injectBanner() {
        if (!OUTBOUND_DISABLED) return true;
        if (document.querySelector('.unicode-banner')) return true;
        var form = loginFormEl();
        if (!form) return false;
        var banner = document.createElement('div');
        banner.className = 'unicode-banner';
        banner.innerHTML =
            '<strong>⚠ 本站当前已关闭发信功能</strong>' +
            '如您有发信需求，请避免使用此邮局（仍可正常收信）。';
        // 插到品牌下面、表单内容上面
        var brand = form.querySelector('.unicode-brand');
        if (brand) brand.parentNode.insertBefore(banner, brand.nextSibling);
        else       form.insertBefore(banner, form.firstChild);
        return true;
    }

    // ---------- Turnstile widget 渲染 ----------

    function loadTurnstileApi() {
        if (window.turnstile) return Promise.resolve();
        if (loadTurnstileApi._p) return loadTurnstileApi._p;
        loadTurnstileApi._p = new Promise(function (resolve, reject) {
            var s = document.createElement('script');
            s.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
            s.async = true;
            s.defer = true;
            s.onload = function () { resolve(); };
            s.onerror = function () { reject(new Error('Turnstile API 加载失败')); };
            document.head.appendChild(s);
        });
        return loadTurnstileApi._p;
    }

    function renderTurnstile() {
        if (!TURNSTILE_ENABLED || !TURNSTILE_SITE_KEY || widgetRendered) return;
        var form = loginFormEl();
        if (!form) return;

        // 容器：插在密码框和登录按钮之间
        var container = form.querySelector('.unicode-turnstile');
        if (!container) {
            container = document.createElement('div');
            container.className = 'unicode-turnstile';
            container.id = 'unicode-turnstile';
            var pw = form.querySelector('input[type="password"]');
            var btn = form.querySelector('button[type="submit"], button.btn-primary, button');
            if (pw && btn && pw.compareDocumentPosition(btn) & Node.DOCUMENT_POSITION_FOLLOWING) {
                btn.parentNode.insertBefore(container, btn);
            } else if (btn) {
                btn.parentNode.insertBefore(container, btn);
            } else {
                form.appendChild(container);
            }
            // widget 没解之前先把登录按钮锁住，避免用户点了空请求被服务端拒了再返工
            if (btn) {
                btn.classList.add('unicode-locked');
                btn.dataset.unicodeOrigDisabled = btn.disabled ? '1' : '0';
                btn.disabled = true;
            }
        }

        loadTurnstileApi().then(function () {
            if (widgetRendered || !window.turnstile) return;
            window.turnstile.render('#unicode-turnstile', {
                sitekey: TURNSTILE_SITE_KEY,
                theme: 'dark',
                callback: function (token) {
                    turnstileToken = token || '';
                    var btn = form.querySelector('button[type="submit"], button.btn-primary, button');
                    if (btn) {
                        btn.classList.remove('unicode-locked');
                        btn.disabled = (btn.dataset.unicodeOrigDisabled === '1');
                    }
                },
                'error-callback': function () {
                    turnstileToken = '';
                },
                'expired-callback': function () {
                    turnstileToken = '';
                    var btn = form.querySelector('button[type="submit"], button.btn-primary, button');
                    if (btn) {
                        btn.classList.add('unicode-locked');
                        btn.disabled = true;
                    }
                }
            });
            widgetRendered = true;
        }).catch(function (e) {
            // API 加载失败：让登录按钮解锁，否则用户彻底进不去（保守的可用性优先）。
            // server 端 hook 仍会发现 token 缺失并拒绝。
            console.warn('[UNICODE] Turnstile API load failed:', e);
            var btn = form.querySelector('button[type="submit"], button.btn-primary, button');
            if (btn) { btn.classList.remove('unicode-locked'); btn.disabled = false; }
        });
    }

    // ---------- 把 token 注入到登录请求里 ----------
    //
    // SnappyMail 的登录走 AJAX（POST 到 /?/Ajax/&q[]=/0/...），用 fetch 或 XHR。
    // 它构造请求时是用 Knockout/Vue observable 拼字段，不会自动带上额外的
    // hidden input。所以我们 monkey-patch fetch 和 XMLHttpRequest.send，
    // 检测到 Ajax 路径且方法为 POST 时把 token 注入到 body 里。
    // server 端在 $_POST['cf-turnstile-response'] 看得到。

    function isLoginRequest(url) {
        if (!url) return false;
        if (typeof url !== 'string') {
            try { url = String(url.url || url); } catch (e) { return false; }
        }
        // SnappyMail Ajax 路径形如 /?/Ajax/&q[]=/0/0/  /?/Ajax/&q[]=/0/0/Login/
        // 用宽匹配，避免不同版本 URL 微调
        return /\/\?\/Ajax\/&q\[\]=\//.test(url) ||
               /\/\?\/Ajax\/$/.test(url) ||
               /\/Ajax\b/.test(url);
    }

    function injectToken(body) {
        if (!turnstileToken) return body;
        if (body instanceof FormData) {
            body.set('cf-turnstile-response', turnstileToken);
            return body;
        }
        if (body instanceof URLSearchParams) {
            body.set('cf-turnstile-response', turnstileToken);
            return body;
        }
        if (typeof body === 'string') {
            // 已经是 urlencoded（SnappyMail 默认）
            // 去掉旧的同名字段防重复
            var stripped = body.replace(/(^|&)cf-turnstile-response=[^&]*/g, '');
            if (stripped.length && stripped[0] === '&') stripped = stripped.substring(1);
            return stripped + (stripped.length ? '&' : '') +
                'cf-turnstile-response=' + encodeURIComponent(turnstileToken);
        }
        return body;
    }

    // fetch
    if (typeof window.fetch === 'function') {
        var _origFetch = window.fetch;
        window.fetch = function (input, init) {
            try {
                var url = (typeof input === 'string') ? input : (input && input.url);
                if (isLoginRequest(url) && init && init.method &&
                    init.method.toUpperCase() === 'POST' && turnstileToken) {
                    init.body = injectToken(init.body);
                }
            } catch (e) { /* 不阻断原请求 */ }
            return _origFetch.apply(this, arguments);
        };
    }

    // XHR
    var _origOpen = XMLHttpRequest.prototype.open;
    var _origSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function (method, url) {
        this._unicodeUrl = url;
        this._unicodeMethod = (method || '').toUpperCase();
        return _origOpen.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function (body) {
        try {
            if (this._unicodeMethod === 'POST' && isLoginRequest(this._unicodeUrl) && turnstileToken) {
                body = injectToken(body);
            }
        } catch (e) { /* 不阻断 */ }
        return _origSend.call(this, body);
    };

    // ---------- 抑制不需要的弹窗 + 隐藏不需要的菜单项 ----------
    //
    // 用 MutationObserver 监听 body 新增节点和子树变化。多种识别策略并用：
    //   - 弹窗：内容文本含「更新身份 / Update Identity / Welcome / 欢迎」→ 点关闭
    //   - 文件夹列表里的「不可见 / Invisible / not visible / Hidden」假节点 → 隐藏
    //   - 设置侧栏的「主题 / Themes」入口 → 隐藏并阻塞跳转
    // 文本识别比 class 名稳定 —— SnappyMail 不同版本 class 名变化大。

    var POPUP_KILL_HINTS = /更新身份|Update Identity|欢迎|welcome|onboard|首次登录/i;
    var INVISIBLE_FOLDER = /^\s*(不可见|invisible|hidden|not\s*visible)\s*$/i;
    var THEME_LABEL      = /^\s*(主题|Themes?|Theme)\s*$/i;

    function killPopup(node) {
        try {
            var txt = (node.textContent || '').slice(0, 400);
            if (!POPUP_KILL_HINTS.test(txt)) return false;
            // 优先点关闭按钮，让 SnappyMail 自己管状态
            var btn = node.querySelector('button.close, .b-close, [data-bind*="closePopup"], [data-bind*="cancelCommand"]');
            if (btn) {
                btn.click();
            } else {
                node.style.display = 'none';
                // 同时清掉可能的 backdrop
                document.querySelectorAll('.modal-backdrop, .b-popup-backdrop').forEach(function (b) {
                    b.style.display = 'none';
                });
            }
            return true;
        } catch (e) { return false; }
    }

    function hideInvisibleFolders(root) {
        // SnappyMail 文件夹列表 ul/li 结构里有一行"不可见"是 system pseudo-folder
        // 用于让用户取消订阅别的文件夹。普通用户看着困惑，隐藏掉。
        try {
            var liList = (root || document).querySelectorAll('li, .b-folder-item');
            liList.forEach(function (li) {
                // 只看直接文本，避免误把含子文件夹的节点也藏了
                var label = li.querySelector('.name, [data-bind*="text"], a, span');
                var t = label ? (label.textContent || '').trim() : '';
                if (INVISIBLE_FOLDER.test(t)) {
                    li.style.display = 'none';
                    li.setAttribute('aria-hidden', 'true');
                }
            });
        } catch (e) { /* ignore */ }
    }

    function hideThemeMenu(root) {
        try {
            // 1) data-route / href 匹配
            (root || document).querySelectorAll(
                'a[href*="themes" i], a[href*="theme" i][href*="settings" i], ' +
                '[data-route*="theme" i], [data-name="Themes"], ' +
                'li[data-name*="theme" i]'
            ).forEach(function (el) { el.style.display = 'none'; });

            // 2) 文本匹配兜底 —— 任意 a/li/span 直接文本是"主题"或"Themes"
            (root || document).querySelectorAll('a, li').forEach(function (el) {
                // 跳过有子 ul 的（避免误把"系统设置"之类带"主题"子菜单的整段藏了）
                if (el.querySelector('ul, .b-folder-list')) return;
                var t = (el.textContent || '').trim();
                if (THEME_LABEL.test(t)) {
                    var li = el.closest ? (el.closest('li') || el) : el;
                    li.style.display = 'none';
                }
            });

            // 3) 如果用户已经在 /settings/themes 路径上，把内容区也清掉
            if (/\/settings\/themes/i.test(location.hash || location.pathname)) {
                var main = document.querySelector('.b-settings-pane, .b-settings, main');
                if (main) {
                    main.innerHTML = '<div style="padding:30px;color:#888">主题已被管理员锁定为 UNICODE。</div>';
                }
            }
        } catch (e) { /* ignore */ }
    }

    function sweep(root) {
        killPopup(root || document.body);
        hideInvisibleFolders(root);
        hideThemeMenu(root);
    }

    // 监听 DOM 变化 —— SnappyMail 异步渲染设置/文件夹列表
    var domObserver = new MutationObserver(function (mutations) {
        mutations.forEach(function (m) {
            m.addedNodes && m.addedNodes.forEach(function (n) {
                if (n.nodeType !== 1) return;
                // 弹窗类：直接判
                if (/popup|modal|b-popup/i.test(n.className || '')) {
                    killPopup(n);
                }
                // 整个子树扫一遍
                sweep(n);
            });
        });
    });
    // 也跑一次 hash change（SnappyMail 是 SPA，路由切换不会触发 DOM mutation）
    window.addEventListener('hashchange', function () {
        setTimeout(function () { sweep(document.body); }, 200);
    });

    // ---------- 启动 ----------

    function start() {
        // 一开始可能 form 还没渲染好，轮询 + observer 双保险
        var tries = 0;
        var iv = setInterval(function () {
            tries++;
            var ok = injectBrand();
            ok = injectBanner() && ok;
            if (TURNSTILE_ENABLED && TURNSTILE_SITE_KEY && loginFormEl()) {
                renderTurnstile();
            }
            // 顺便 sweep 一次（覆盖登录后初始渲染漏掉的情况）
            sweep(document.body);
            // 60 次 ≈ 30 秒后还没出来就放弃（用户大概不在登录页）
            if ((ok && (widgetRendered || !TURNSTILE_ENABLED)) || tries > 60) {
                clearInterval(iv);
            }
        }, 500);

        domObserver.observe(document.body, { childList: true, subtree: true });
        // 第一帧立刻扫一次（不等 mutation）
        sweep(document.body);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start);
    } else {
        start();
    }
})();
