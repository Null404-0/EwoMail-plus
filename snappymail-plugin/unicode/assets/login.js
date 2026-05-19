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

    // ---------- 抑制登录后的欢迎弹窗 ----------
    //
    // SnappyMail 不同版本里"每次登录都跳的提示"对应不同 modal。这里用
    // MutationObserver 监听 <body> 新增节点，匹配几种常见 class / 文案就
    // 直接 dismiss。文案识别保守 —— 只挑包含「welcome / 欢迎 /
    // 提示 / change.*password」字眼的（避免把别的弹窗也吞掉）。

    var WELCOME_HINTS = /欢迎|welcome|onboard|首次登录/i;

    function dismissWelcome(node) {
        try {
            var txt = (node.textContent || '').slice(0, 200);
            if (!WELCOME_HINTS.test(txt)) return;
            // 优先点 modal 的关闭按钮（CSS 可能用 fade-out 动画，直接 remove 太粗）
            var btn = node.querySelector('button.close, .b-close, [data-bind*="close"]');
            if (btn) {
                btn.click();
            } else {
                node.style.display = 'none';
            }
        } catch (e) { /* ignore */ }
    }

    var welcomeObserver = new MutationObserver(function (mutations) {
        mutations.forEach(function (m) {
            m.addedNodes && m.addedNodes.forEach(function (n) {
                if (n.nodeType !== 1) return;
                // 直接是 popup 容器
                if (/popup|modal|notification/.test(n.className || '')) {
                    dismissWelcome(n);
                }
                // 或者子树里
                if (typeof n.querySelectorAll === 'function') {
                    n.querySelectorAll('.popup, .modal, .notification').forEach(dismissWelcome);
                }
            });
        });
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
            // 60 次 ≈ 30 秒后还没出来就放弃（用户大概不在登录页）
            if ((ok && (widgetRendered || !TURNSTILE_ENABLED)) || tries > 60) {
                clearInterval(iv);
            }
        }, 500);

        welcomeObserver.observe(document.body, { childList: true, subtree: true });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start);
    } else {
        start();
    }
})();
