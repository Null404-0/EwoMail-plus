# UI helpers: coloured output, progress, prompts.
# Sourced from install.sh; do not execute directly.

if [[ -t 1 ]]; then
    UI_BOLD="$(printf '\033[1m')"
    UI_DIM="$(printf '\033[2m')"
    UI_RED="$(printf '\033[31m')"
    UI_GREEN="$(printf '\033[32m')"
    UI_YELLOW="$(printf '\033[33m')"
    UI_BLUE="$(printf '\033[34m')"
    UI_CYAN="$(printf '\033[36m')"
    UI_RESET="$(printf '\033[0m')"
else
    UI_BOLD=""; UI_DIM=""; UI_RED=""; UI_GREEN=""; UI_YELLOW=""; UI_BLUE=""; UI_CYAN=""; UI_RESET=""
fi

UI_STEP_INDEX=0
UI_STEP_TOTAL=14

ui_banner() {
    local title="$1"
    local width=64
    local pad=$(( (width - ${#title}) / 2 ))
    printf '\n%s' "${UI_CYAN}${UI_BOLD}"
    printf '═%.0s' $(seq 1 "$width")
    printf '\n%*s%s%*s\n' "$pad" '' "$title" "$pad" ''
    printf '═%.0s' $(seq 1 "$width")
    printf '%s\n\n' "${UI_RESET}"
}

ui_info()   { printf '%s[i]%s %s\n' "${UI_BLUE}"   "${UI_RESET}" "$*"; }
ui_ok()     { printf '%s[✓]%s %s\n' "${UI_GREEN}"  "${UI_RESET}" "$*"; }
ui_warn()   { printf '%s[!]%s %s\n' "${UI_YELLOW}" "${UI_RESET}" "$*" >&2; }
ui_err()    { printf '%s[x]%s %s\n' "${UI_RED}"    "${UI_RESET}" "$*" >&2; }
ui_dim()    { printf '%s%s%s\n'     "${UI_DIM}"    "$*"            "${UI_RESET}"; }

step() {
    UI_STEP_INDEX=$(( UI_STEP_INDEX + 1 ))
    local label="$1"
    printf '\n%s[%d/%d]%s %s%s%s\n' \
        "${UI_CYAN}" "${UI_STEP_INDEX}" "${UI_STEP_TOTAL}" "${UI_RESET}" \
        "${UI_BOLD}" "${label}" "${UI_RESET}"
}

init_logging() {
    mkdir -p "$(dirname "${LOG_FILE}")"
    : > "${LOG_FILE}"
    chmod 600 "${LOG_FILE}"
    ui_dim "详细日志 → ${LOG_FILE}"
}

log() {
    printf '[%s] %s\n' "$(date -Iseconds)" "$*" >> "${LOG_FILE}"
}

run() {
    log "EXEC: $*"
    if "$@" >>"${LOG_FILE}" 2>&1; then
        return 0
    else
        local rc=$?
        ui_err "命令失败（退出码 ${rc}）：$*"
        ui_err "详见 ${LOG_FILE} 的最后部分。"
        tail -n 20 "${LOG_FILE}" | sed 's/^/    /'
        return "$rc"
    fi
}

run_quiet() {
    log "EXEC (quiet): $*"
    "$@" >>"${LOG_FILE}" 2>&1
}

# Like run(), but tees output to both terminal and log file so the user sees
# progress for long-running commands (apt install, dhparam gen, freshclam).
# Output is lightly indented so it visually separates from our [i]/[✓] lines.
run_stream() {
    log "EXEC (stream): $*"
    local rc=0
    if "$@" 2>&1 | tee -a "${LOG_FILE}" | sed 's/^/  │ /'; then
        rc=${PIPESTATUS[0]}
    else
        rc=${PIPESTATUS[0]}
    fi
    if (( rc != 0 )); then
        ui_err "命令失败（退出码 ${rc}）：$*"
        return "$rc"
    fi
    return 0
}

on_error() {
    local rc=$?
    ui_err "安装中断（退出码 ${rc}）。请查看 ${LOG_FILE}。"
    exit "$rc"
}

require_root() {
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
        ui_err "本安装器必须以 root 身份运行。"
        exit 1
    fi
}

confirm_proceed() {
    echo
    printf '%s准备就绪，是否开始安装？[y/N]：%s ' "${UI_BOLD}" "${UI_RESET}"
    local ans
    read -r ans
    case "${ans,,}" in
        y|yes) ;;
        *) ui_err "用户取消。"; exit 1 ;;
    esac
}

prompt_default() {
    # prompt_default <question> <default_value> <varname>
    local q="$1" def="$2" var="$3" ans=""
    printf '%s%s%s [%s]: ' "${UI_BOLD}" "${q}" "${UI_RESET}" "${def}"
    read -r ans
    [[ -z "${ans}" ]] && ans="${def}"
    printf -v "${var}" '%s' "${ans}"
}

prompt_yesno() {
    # prompt_yesno <question> <default_yes|no> <varname>
    local q="$1" def="$2" var="$3" ans=""
    local hint
    [[ "${def}" == "yes" ]] && hint="Y/n" || hint="y/N"
    printf '%s%s%s [%s]: ' "${UI_BOLD}" "${q}" "${UI_RESET}" "${hint}"
    read -r ans
    if [[ -z "${ans}" ]]; then ans="${def}"; fi
    case "${ans,,}" in
        y|yes) printf -v "${var}" '%s' "yes" ;;
        *)     printf -v "${var}" '%s' "no" ;;
    esac
}
