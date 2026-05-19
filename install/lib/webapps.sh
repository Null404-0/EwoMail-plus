# Pulls EwoMail-Admin, SnappyMail, Adminer into /ewomail/www.

# Default to pinned, verified versions. The installer first tries to query
# GitHub's /releases/latest API to pick up newer versions automatically;
# the pins below are the fallback when that call fails (no internet to
# api.github.com, rate-limited, etc.).
SNAPPYMAIL_PIN_VERSION="2.38.2"
ADMINER_PIN_VERSION="4.8.4"

_fetch() {
    local url="$1" dest="$2"
    log "Fetching ${url} → ${dest}"
    if ! curl -fSL --connect-timeout 15 --max-time 600 -o "${dest}" "${url}" >>"${LOG_FILE}" 2>&1; then
        ui_warn "下载 ${url} 失败，重试一次。"
        sleep 3
        curl -fSL --connect-timeout 15 --max-time 600 -o "${dest}" "${url}" >>"${LOG_FILE}" 2>&1
    fi
}

# Returns a download URL for the first asset whose name matches the given
# regex on a GitHub /releases/latest response. Prints empty string on failure.
_latest_asset_url() {
    local repo="$1" name_regex="$2"
    local api="https://api.github.com/repos/${repo}/releases/latest"
    local body
    body=$(curl -fsSL --connect-timeout 10 --max-time 30 \
                -H 'Accept: application/vnd.github+json' "${api}" 2>>"${LOG_FILE}") || return 1
    # Pick out browser_download_url whose corresponding name matches the regex.
    # Avoid jq dependency by doing this with grep -P and a small awk pass.
    printf '%s' "${body}" \
        | grep -Eo '"(name|browser_download_url)": ?"[^"]+"' \
        | awk -F'"' -v re="${name_regex}" '
            $2=="name"                 {n=$4; next}
            $2=="browser_download_url" && n ~ re {print $4; exit}
          '
}

install_webapps() {
    install -d -m 0755 /ewomail/www
    install -d -m 0755 /ewomail/www/default
    install -d -m 0755 /ewomail/www/session
    install -d -m 0755 /ewomail/www/session/ewomail-admin
    install -d -m 0755 /ewomail/www/session/webmail
    install -d -m 0755 /ewomail/www/session/adminer

    # 1. EwoMail-Admin (from this repository).
    if [[ -e /ewomail/www/ewomail-admin ]]; then rm -rf /ewomail/www/ewomail-admin; fi
    cp -a "${REPO_DIR}/ewomail-admin" /ewomail/www/ewomail-admin

    # Default landing page (placeholder explaining where to go).
    render_template "${INSTALLER_DIR}/templates/snappymail/index.html" /ewomail/www/default/index.html

    # 2. SnappyMail. Try the GitHub API first; fall back to a pinned URL.
    local snappy_zip="/tmp/snappymail.zip"
    if [[ ! -d /ewomail/www/snappymail/.installed ]]; then
        local snappy_url
        snappy_url=$(_latest_asset_url "the-djmaze/snappymail" '^snappymail-[0-9.]+[.]zip$' || true)
        if [[ -z "${snappy_url}" ]]; then
            snappy_url="https://github.com/the-djmaze/snappymail/releases/download/v${SNAPPYMAIL_PIN_VERSION}/snappymail-${SNAPPYMAIL_PIN_VERSION}.zip"
            ui_info "GitHub API 不可达，回退到固定版本 SnappyMail ${SNAPPYMAIL_PIN_VERSION}"
        else
            ui_info "SnappyMail 资源：${snappy_url}"
        fi
        _fetch "${snappy_url}" "${snappy_zip}"
        install -d -m 0755 /ewomail/www/snappymail
        run unzip -q -o "${snappy_zip}" -d /ewomail/www/snappymail
        rm -f "${snappy_zip}"

        # Flatten if the zip wrapped its contents in a top-level dir.
        if [[ ! -f /ewomail/www/snappymail/index.php ]]; then
            local inner; inner=$(find /ewomail/www/snappymail -maxdepth 2 -name 'index.php' -printf '%h\n' | head -1)
            if [[ -n "${inner}" && "${inner}" != "/ewomail/www/snappymail" ]]; then
                ui_info "展开 SnappyMail 嵌套目录：${inner}"
                shopt -s dotglob
                mv "${inner}"/* /ewomail/www/snappymail/
                shopt -u dotglob
                rmdir "${inner}" 2>/dev/null || true
            fi
        fi
        if [[ ! -f /ewomail/www/snappymail/index.php ]]; then
            ui_err "SnappyMail 解压后未找到 index.php"
            return 1
        fi
        touch /ewomail/www/snappymail/.installed
    fi

    # 3. Adminer (single PHP file).
    install -d -m 0755 /ewomail/www/adminer
    if [[ ! -f /ewomail/www/adminer/index.php ]]; then
        local adminer_url
        adminer_url=$(_latest_asset_url "vrana/adminer" '^adminer-[0-9.]+-mysql[.]php$' || true)
        if [[ -z "${adminer_url}" ]]; then
            adminer_url="https://github.com/vrana/adminer/releases/download/v${ADMINER_PIN_VERSION}/adminer-${ADMINER_PIN_VERSION}-mysql.php"
            ui_info "GitHub API 不可达，回退到固定版本 Adminer ${ADMINER_PIN_VERSION}"
        else
            ui_info "Adminer 资源：${adminer_url}"
        fi
        _fetch "${adminer_url}" /ewomail/www/adminer/index.php
    fi

    # Permissions for php-fpm user (www-data).
    chown -R www-data:www-data /ewomail/www
    find /ewomail/www -type d -exec chmod 0755 {} +
    find /ewomail/www -type f -exec chmod 0644 {} +
    chmod -R 0770 /ewomail/www/session
    chown -R www-data:www-data /ewomail/www/session

    # SnappyMail keeps storage (user prefs, encrypted credentials) under
    # /ewomail/www/snappymail/data. Restrict it to the www-data group only.
    if [[ -d /ewomail/www/snappymail/data ]]; then
        chmod 0750 /ewomail/www/snappymail/data
        find /ewomail/www/snappymail/data -type d -exec chmod 0750 {} +
        find /ewomail/www/snappymail/data -type f -exec chmod 0640 {} +
    fi

    install_unicode_plugin

    ui_ok "Web 应用已安装到 /ewomail/www"
}

# 把 UNICODE webmail 品牌 plugin 部署到 SnappyMail data 目录，并启用 +
# 写一份默认配置（turnstile 关、outbound 正常）。装机阶段调，admin_init
# 还没渲染 /ewomail/sbin/ewomail-helper —— 我们直接 bash 跑模板里的同一份
# 代码（snappy-plugin-{enable,config-write} 这两个 case 分支自包含、不
# 依赖任何环境变量，root 直接 bash 跑没问题）。
install_unicode_plugin() {
    local src="${REPO_DIR}/snappymail-plugin/unicode"
    local dst="/ewomail/www/snappymail/data/_data_/_default_/plugins/unicode"

    if [[ ! -d "${src}" ]]; then
        ui_warn "未找到 ${src}，跳过 UNICODE plugin 部署"
        return 0
    fi

    install -d -m 0750 -o www-data -g www-data \
        /ewomail/www/snappymail/data/_data_/_default_/plugins
    rm -rf "${dst}"
    cp -a "${src}" "${dst}"

    # 权限：root 拥有，www-data 读
    chown -R root:www-data "${dst}"
    find "${dst}" -type d -exec chmod 0750 {} +
    find "${dst}" -type f -exec chmod 0640 {} +
    # assets/* 要走 webroot 给浏览器读，必须 world-readable
    if [[ -d "${dst}/assets" ]]; then
        chmod 0755 "${dst}/assets"
        find "${dst}/assets" -type f -exec chmod 0644 {} +
    fi

    # 用 helper 模板直接执行（admin_init.sh 还没把它装到 /ewomail/sbin/）
    local helper_tmpl="${INSTALLER_DIR}/templates/admin-helper/ewomail-helper"
    if [[ -x "${helper_tmpl}" ]] || [[ -f "${helper_tmpl}" ]]; then
        bash "${helper_tmpl}" snappy-plugin-enable unicode \
            >>"${LOG_FILE}" 2>&1 || ui_warn "snappy-plugin-enable 失败（详见日志）"
        printf '%s' '{"turnstile_enabled":"no","turnstile_site_key":"","turnstile_secret_key":"","outbound_disabled":"no"}' \
            | bash "${helper_tmpl}" snappy-plugin-config-write unicode \
            >>"${LOG_FILE}" 2>&1 || ui_warn "snappy-plugin-config-write 失败（详见日志）"
        # 默认主题切到 Black Wood（用户没手动改过的话）。SnappyMail bootstrap 写
        # application.ini 时默认 theme="Default"，我们覆盖一次。
        bash "${helper_tmpl}" snappy-set-theme "Black Wood" \
            >>"${LOG_FILE}" 2>&1 || ui_warn "snappy-set-theme 失败（详见日志）"
    fi

    ui_ok "UNICODE plugin 已部署到 SnappyMail（默认 Turnstile 关闭，可在面板里启用）"
}
