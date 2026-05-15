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
UI_STEP_TOTAL=16

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
    ui_dim "Detailed log → ${LOG_FILE}"
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
        ui_err "Command failed (rc=${rc}): $*"
        ui_err "See last lines of ${LOG_FILE} for details."
        tail -n 20 "${LOG_FILE}" | sed 's/^/    /'
        return "$rc"
    fi
}

run_quiet() {
    log "EXEC (quiet): $*"
    "$@" >>"${LOG_FILE}" 2>&1
}

on_error() {
    local rc=$?
    ui_err "Installation aborted (exit ${rc}). Inspect ${LOG_FILE}."
    exit "$rc"
}

require_root() {
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
        ui_err "This installer must be run as root."
        exit 1
    fi
}

confirm_proceed() {
    echo
    printf '%sReady to install. Continue? [y/N]:%s ' "${UI_BOLD}" "${UI_RESET}"
    local ans
    read -r ans
    case "${ans,,}" in
        y|yes) ;;
        *) ui_err "Aborted by user."; exit 1 ;;
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
