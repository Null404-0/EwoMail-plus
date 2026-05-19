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
    // 用 MutationObserver 监听 body 新增节点和子树变化。
    // - 弹窗：内容文本含「更新身份 / Update Identity / Welcome / 欢迎」→ 点关闭
    // - 文件夹列表里 SnappyMail 的「filter unseen」勾选框（中文 i18n 翻成
    //   "不可见"，意义不明）→ data-bind 精准匹配隐藏

    var POPUP_KILL_HINTS = /更新身份|Update Identity|欢迎|welcome|onboard|首次登录/i;

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

    function hideInvisibleToggle(root) {
        // SnappyMail 文件夹列表里有一行 toggle: filterUnseen 的 checkbox，
        // 中文 i18n 译成"不可见"显得莫名其妙，隐藏掉。
        // 用 data-bind 精准匹配比文本匹配可靠（不同语言都有效）。
        try {
            (root || document).querySelectorAll('[data-bind*="filterUnseen"]').forEach(function (el) {
                var container = (el.closest && el.closest('.e-checkbox')) || el;
                container.style.display = 'none';
            });
        } catch (e) { /* ignore */ }
    }

    function sweep(root) {
        killPopup(root || document.body);
        hideInvisibleToggle(root);
        injectPasswordMenu(root);
    }

    // ---------- "密码" 设置入口 ----------
    //
    // SnappyMail 2.38 自带的 change-password plugin 只支持 poppassd / ldap /
    // virtualmin 几个后端，没 MySQL（EwoMail 的密码存 i_users.password 是 MD5）。
    // 我们自己加一个：
    //   1. 在 Settings 侧栏的"安全"后面插一行"密码"
    //   2. 点击 → 弹自定义 modal → 填当前 / 新 / 确认
    //   3. 提交到 UnicodeChangePassword JSON 端点（addJsonHook 注册的，PHP 端
    //      自己接 EwoMail DB 改 i_users）
    //
    // 用 Knockout-friendly 的 attribute hooks，避开和 SnappyMail 自己的 binding
    // 打架。SnappyMail 路由切换会重新渲染菜单，导致我们注入的链接消失 ——
    // MutationObserver 每次都会再 sweep 进来补上。

    function injectPasswordMenu(root) {
        try {
            // 只在 Settings 页面（路由 #/settings/...）注入
            if (!/\#\/settings/i.test(location.hash || '')) return;
            // 找设置侧栏的 nav
            var navs = (root || document).querySelectorAll('nav, .b-settings-menu nav, [data-bind*="foreach: menu"]');
            navs.forEach(function (nav) {
                // 已经注入过就跳
                if (nav.querySelector('[data-unicode-pw]')) return;
                // 至少要有几个原生菜单项再注入，防误注入到其他 nav
                var existing = nav.querySelectorAll('a[data-i18n], a[href*="settings/"]');
                if (existing.length < 2) return;

                var link = document.createElement('a');
                link.setAttribute('data-unicode-pw', '1');
                link.setAttribute('href', 'javascript:;');
                link.textContent = '密码';
                link.style.cursor = 'pointer';
                // 复制兄弟 link 的 class，视觉跟原生一致
                var sibling = existing[0];
                if (sibling && sibling.className) link.className = sibling.className;
                link.addEventListener('click', function (e) {
                    e.preventDefault();
                    e.stopPropagation();
                    // 取消别的 "selected" 状态，给自己加上
                    nav.querySelectorAll('a.selected').forEach(function (a) { a.classList.remove('selected'); });
                    link.classList.add('selected');
                    showPasswordModal();
                });

                // 插在"安全"之后；找不到就在末尾
                var security = Array.from(existing).find(function (a) {
                    var i18n = (a.getAttribute('data-i18n') || '').toLowerCase();
                    var href = (a.getAttribute('href') || '').toLowerCase();
                    return /security/.test(i18n) || /security/.test(href);
                });
                if (security && security.nextSibling) {
                    nav.insertBefore(link, security.nextSibling);
                } else {
                    nav.appendChild(link);
                }
            });
        } catch (e) { /* ignore */ }
    }

    function showPasswordModal() {
        // 如果已经有 modal 就别重复开
        if (document.getElementById('unicode-pw-modal')) return;

        var html =
            '<div id="unicode-pw-modal" style="position:fixed;inset:0;background:rgba(0,0,0,0.65);z-index:99999;display:flex;align-items:center;justify-content:center;">' +
              '<div style="background:#1a1a1a;color:#e5e5e5;padding:28px 32px;border-radius:6px;border:1px solid #dc143c;width:420px;max-width:92vw;box-shadow:0 10px 50px rgba(0,0,0,0.7),0 0 0 1px rgba(220,20,60,0.15);">' +
                '<h3 style="margin:0 0 18px;color:#dc143c;font-size:18px;font-weight:700;letter-spacing:1px">修改密码</h3>' +
                '<form id="unicode-pw-form">' +
                  '<div style="margin-bottom:14px">' +
                    '<label style="display:block;margin-bottom:5px;font-size:13px;color:#bbb">当前密码</label>' +
                    '<input type="password" name="old" required ' +
                      'style="width:100%;padding:9px 10px;background:#222;border:1px solid #3a3a3a;color:#eee;border-radius:3px;box-sizing:border-box">' +
                  '</div>' +
                  '<div style="margin-bottom:14px">' +
                    '<label style="display:block;margin-bottom:5px;font-size:13px;color:#bbb">新密码（8-64 位）</label>' +
                    '<input type="password" name="newp" required minlength="8" maxlength="64" ' +
                      'style="width:100%;padding:9px 10px;background:#222;border:1px solid #3a3a3a;color:#eee;border-radius:3px;box-sizing:border-box">' +
                  '</div>' +
                  '<div style="margin-bottom:16px">' +
                    '<label style="display:block;margin-bottom:5px;font-size:13px;color:#bbb">再次输入新密码</label>' +
                    '<input type="password" name="confirm" required ' +
                      'style="width:100%;padding:9px 10px;background:#222;border:1px solid #3a3a3a;color:#eee;border-radius:3px;box-sizing:border-box">' +
                  '</div>' +
                  '<div id="unicode-pw-msg" style="min-height:1.4em;margin-bottom:12px;font-size:13px;color:#dc143c"></div>' +
                  '<div style="display:flex;gap:10px;">' +
                    '<button type="submit" style="flex:1;padding:10px;background:linear-gradient(180deg,#dc143c,#b30f30);color:#fff;border:none;border-radius:3px;cursor:pointer;font-weight:600;letter-spacing:1px">修改</button>' +
                    '<button type="button" id="unicode-pw-cancel" style="flex:1;padding:10px;background:#3a3a3a;color:#ccc;border:none;border-radius:3px;cursor:pointer">取消</button>' +
                  '</div>' +
                '</form>' +
              '</div>' +
            '</div>';
        document.body.insertAdjacentHTML('beforeend', html);

        function close() {
            var m = document.getElementById('unicode-pw-modal');
            if (m) m.remove();
        }
        document.getElementById('unicode-pw-cancel').addEventListener('click', close);
        // ESC 关闭
        document.addEventListener('keydown', function onEsc(e) {
            if (e.key === 'Escape') { close(); document.removeEventListener('keydown', onEsc); }
        });

        document.getElementById('unicode-pw-form').addEventListener('submit', function (e) {
            e.preventDefault();
            var f = e.target;
            var msg = document.getElementById('unicode-pw-msg');
            msg.style.color = '#dc143c';

            var oldp = f.old.value, newp = f.newp.value, cfm = f.confirm.value;
            if (newp !== cfm) { msg.textContent = '两次输入的新密码不一致'; return; }
            if (newp.length < 8 || newp.length > 64) { msg.textContent = '新密码长度需 8-64 位'; return; }
            if (oldp === newp) { msg.textContent = '新密码不能和当前密码相同'; return; }

            msg.style.color = '#bbb';
            msg.textContent = '提交中…';

            changePasswordRequest(oldp, newp).then(function (j) {
                var res = (j && j.Result) || j || {};
                if (res.success) {
                    msg.style.color = '#43a047';
                    msg.textContent = res.message || '密码已修改，2 秒后自动退出登录…';
                    // 修改成功后强制重新登录（让新密码生效）
                    setTimeout(function () {
                        // SnappyMail 登出走 #/logout 或者直接清 cookie
                        try { document.cookie.split(';').forEach(function (c) {
                            document.cookie = c.replace(/^ +/, '').replace(/=.*/, '=;expires=' + new Date().toUTCString() + ';path=/');
                        }); } catch (e) {}
                        location.href = '/';
                    }, 2000);
                } else {
                    msg.style.color = '#dc143c';
                    msg.textContent = res.error || '修改失败';
                }
            }).catch(function (e) {
                msg.style.color = '#dc143c';
                msg.textContent = '请求失败：' + (e && e.message || e);
            });
        });
    }

    function changePasswordRequest(oldp, newp) {
        // SnappyMail 的 plugin addJsonHook 路由 URL 在不同版本里可能略不同，
        // 试两种最常见的 pattern。一种成功就 return。
        var paths = [
            '/?/Json/&q[]=/0/0/UnicodeChangePassword/',
            '/?/UnicodeChangePassword/0/' + Math.random().toString(36).slice(2) + '/'
        ];
        var body = new URLSearchParams({ OldPassword: oldp, NewPassword: newp });
        var token = '';
        try {
            if (window.rl && window.rl.settings && typeof window.rl.settings.app === 'function') {
                token = window.rl.settings.app('token') || '';
            }
        } catch (e) {}
        var headers = {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'application/json',
            'X-SM-Token': token
        };

        function tryNext(i) {
            if (i >= paths.length) return Promise.reject(new Error('所有路径都失败'));
            return fetch(paths[i], { method: 'POST', body: body, headers: headers, credentials: 'same-origin' })
                .then(function (r) {
                    if (!r.ok) throw new Error('HTTP ' + r.status);
                    return r.json();
                })
                .then(function (j) {
                    // 如果 SnappyMail 不认这个 action 名，会返回 {Action: ..., ErrorCode: ...} 或类似
                    if (j && j.Result && typeof j.Result === 'object') return j;
                    if (j && j.error) throw new Error(j.error);
                    if (j && j.ErrorCode) throw new Error('SnappyMail 返回 ErrorCode=' + j.ErrorCode);
                    return j;
                })
                .catch(function (e) {
                    if (i + 1 < paths.length) return tryNext(i + 1);
                    throw e;
                });
        }
        return tryNext(0);
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
