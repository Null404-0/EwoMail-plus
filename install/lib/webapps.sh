# Pulls EwoMail-Admin, SnappyMail, Adminer into /ewomail/www.

SNAPPYMAIL_VERSION="2.38.3"
ADMINER_VERSION="4.8.4"   # last 4.x stable (2023); 5.x is still alpha

_fetch() {
    local url="$1" dest="$2"
    log "Fetching ${url} → ${dest}"
    if ! curl -fSL --connect-timeout 15 --max-time 600 -o "${dest}" "${url}" >>"${LOG_FILE}" 2>&1; then
        ui_warn "Failed to fetch ${url}; will retry once."
        sleep 3
        curl -fSL --connect-timeout 15 --max-time 600 -o "${dest}" "${url}" >>"${LOG_FILE}" 2>&1
    fi
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

    # 2. SnappyMail.
    local snappy_zip="/tmp/snappymail.zip"
    if [[ ! -d /ewomail/www/snappymail ]]; then
        _fetch "https://github.com/the-djmaze/snappymail/releases/download/v${SNAPPYMAIL_VERSION}/snappymail-${SNAPPYMAIL_VERSION}.zip" "${snappy_zip}"
        install -d -m 0755 /ewomail/www/snappymail
        run unzip -q -o "${snappy_zip}" -d /ewomail/www/snappymail
        rm -f "${snappy_zip}"
        # SnappyMail zips have historically been flat (no top-level dir), but
        # some releases wrap their files in one. Flatten if needed.
        if [[ ! -f /ewomail/www/snappymail/index.php ]]; then
            local inner; inner=$(find /ewomail/www/snappymail -maxdepth 2 -name 'index.php' -printf '%h\n' | head -1)
            if [[ -n "${inner}" && "${inner}" != "/ewomail/www/snappymail" ]]; then
                ui_info "Flattening SnappyMail archive from ${inner}"
                shopt -s dotglob
                mv "${inner}"/* /ewomail/www/snappymail/
                shopt -u dotglob
                rmdir "${inner}" 2>/dev/null || true
            fi
        fi
        if [[ ! -f /ewomail/www/snappymail/index.php ]]; then
            ui_err "SnappyMail extraction did not produce index.php"
            return 1
        fi
    fi

    # 3. Adminer (single PHP file).
    install -d -m 0755 /ewomail/www/adminer
    if [[ ! -f /ewomail/www/adminer/index.php ]]; then
        _fetch "https://github.com/vrana/adminer/releases/download/v${ADMINER_VERSION}/adminer-${ADMINER_VERSION}-mysql.php" \
               /ewomail/www/adminer/index.php
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

    ui_ok "Web applications installed under /ewomail/www"
}
