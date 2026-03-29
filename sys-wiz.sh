#!/bin/sh

set -e

# ── Constants ─────────────────────────────────────────────────────────────────
SCRIPT_NAME="sys-wiz"
SCRIPT_VERSION="2.0"
SCRIPT_AUTHOR="github.com/aam-007/sys-wiz"

CONF_DIR="${HOME}/.config/sys-wiz"
DATA_DIR="${HOME}/.local/share/sys-wiz"
CONF_FILE="${CONF_DIR}/sys-wiz.conf"
LOG_FILE="${DATA_DIR}/sys-wiz.log"
HIST_FILE="${DATA_DIR}/command-history.log"
PLUGIN_DIR="${CONF_DIR}/plugins"
ROLLBACK_FILE="${DATA_DIR}/rollback-ids"
LOCK_FILE="/tmp/sys-wiz-$$.lock"

MAX_ROLLBACK=20       # keep last N transaction IDs
LOG_MAX_LINES=10000   # rotate log after this many lines
SEARCH_LIMIT=25       # max results shown from dnf search

# ── Colour palette (populated after terminal check) ───────────────────────────
C_RESET="" C_BOLD="" C_DIM=""
C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_MAGENTA="" C_CYAN="" C_WHITE=""
C_BG_RED="" C_BG_GREEN="" C_BG_BLUE=""
C_BRED="" C_BGREEN="" C_BYELLOW="" C_BBLUE="" C_BMAGENTA="" C_BCYAN=""

# ── Runtime state ─────────────────────────────────────────────────────────────
DRY_RUN=0       # 1 = preview only, never execute
VERBOSE=0       # 1 = show extra debug info
ASSUME_YES=0    # 1 = skip interactive confirmation prompts
QUIET=0         # 1 = suppress spinner/progress noise
BATCH_MODE=0    # 1 = non-interactive; implies ASSUME_YES
DIALOG=none     # whiptail | dialog | none
FEDORA_VER=""
DNF_VER=""

# =============================================================================
# SECTION 1 — TERMINAL & ENVIRONMENT SETUP
# =============================================================================

setup_terminal() {
    # Detect colour support
    _ncolors=0
    if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
        _ncolors=$(tput colors 2>/dev/null || echo 0)
    fi

    if [ "$_ncolors" -ge 8 ] 2>/dev/null; then
        C_RESET=$(printf '\033[0m')
        C_BOLD=$(printf '\033[1m')
        C_DIM=$(printf '\033[2m')
        C_RED=$(printf '\033[31m')
        C_GREEN=$(printf '\033[32m')
        C_YELLOW=$(printf '\033[33m')
        C_BLUE=$(printf '\033[34m')
        C_MAGENTA=$(printf '\033[35m')
        C_CYAN=$(printf '\033[36m')
        C_WHITE=$(printf '\033[37m')
        C_BRED=$(printf '\033[91m')
        C_BGREEN=$(printf '\033[92m')
        C_BYELLOW=$(printf '\033[93m')
        C_BBLUE=$(printf '\033[94m')
        C_BMAGENTA=$(printf '\033[95m')
        C_BCYAN=$(printf '\033[96m')
        C_BG_RED=$(printf '\033[41m')
        C_BG_GREEN=$(printf '\033[42m')
        C_BG_BLUE=$(printf '\033[44m')
    fi

    # Detect best dialog backend
    if command -v whiptail >/dev/null 2>&1; then
        DIALOG=whiptail
    elif command -v dialog >/dev/null 2>&1; then
        DIALOG=dialog
    fi

    # Detect terminal width; default 80
    TERM_WIDTH=80
    if command -v tput >/dev/null 2>&1; then
        _w=$(tput cols 2>/dev/null || echo 80)
        [ "$_w" -gt 40 ] 2>/dev/null && TERM_WIDTH=$_w
    fi
}

# =============================================================================
# SECTION 2 — LOGGING
# =============================================================================

_ensure_dirs() {
    mkdir -p "$CONF_DIR" "$DATA_DIR" "$PLUGIN_DIR" 2>/dev/null || true
}

_log() {
    _level="$1"; shift
    _msg="$*"
    _ts=$(date '+%Y-%m-%d %H:%M:%S')
    printf '%s [%s] %s\n' "$_ts" "$_level" "$_msg" >> "$LOG_FILE" 2>/dev/null || true

    # Rotate log when it grows too large
    if [ -f "$LOG_FILE" ]; then
        _lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$_lines" -gt "$LOG_MAX_LINES" ] 2>/dev/null; then
            _tmp="${LOG_FILE}.tmp"
            tail -n $(( LOG_MAX_LINES / 2 )) "$LOG_FILE" > "$_tmp" 2>/dev/null && mv "$_tmp" "$LOG_FILE" 2>/dev/null || true
        fi
    fi
}

log_info()  { _log INFO  "$@"; }
log_warn()  { _log WARN  "$@"; }
log_error() { _log ERROR "$@"; }
log_debug() { [ "$VERBOSE" -eq 1 ] && _log DEBUG "$@" || true; }

_log_cmd() {
    _ts=$(date '+%Y-%m-%d %H:%M:%S')
    printf '%s  %s\n' "$_ts" "$*" >> "$HIST_FILE" 2>/dev/null || true
}

# =============================================================================
# SECTION 3 — OUTPUT HELPERS
# =============================================================================

println()  { printf '%s\n' "$*"; }
print_nl() { printf '\n'; }

# Coloured prefixed messages
msg_info()    { printf '  %s%s%s %s\n'   "$C_BCYAN"    "●" "$C_RESET" "$*"; }
msg_ok()      { printf '  %s%s%s %s\n'   "$C_BGREEN"   "✔" "$C_RESET" "$*"; }
msg_warn()    { printf '  %s%s%s %s\n'   "$C_BYELLOW"  "⚠" "$C_RESET" "$*"; }
msg_error()   { printf '  %s%s%s %s\n'   "$C_BRED"     "✖" "$C_RESET" "$*" >&2; }
msg_step()    { printf '  %s%s%s %s\n'   "$C_BBLUE"    "→" "$C_RESET" "$*"; }
msg_dim()     { printf '  %s%s%s\n'      "$C_DIM"      "$*" "$C_RESET"; }
msg_dry()     { printf '  %s[DRY-RUN]%s %s\n' "$C_BMAGENTA" "$C_RESET" "$*"; }

# Horizontal rule
hr() {
    _chr="${1:--}"
    _len="${TERM_WIDTH}"
    printf '%s' "$C_DIM"
    i=0; while [ "$i" -lt "$_len" ]; do printf '%s' "$_chr"; i=$(( i + 1 )); done
    printf '%s\n' "$C_RESET"
}

# Section header
section() {
    print_nl
    hr "─"
    printf '  %s%s%s  %s\n' "$C_BOLD" "$C_BCYAN" "$1" "$C_RESET"
    hr "─"
}

# Banner
banner() {
    clear
    printf '%s' "$C_BOLD$C_BBLUE"
    cat <<'BANNER'
  ┌─────────────────────────────────────────────────────┐
  │                                                     │
  │    ███████╗██╗   ██╗███████╗      ██╗    ██╗██╗    │
  │    ██╔════╝╚██╗ ██╔╝██╔════╝      ██║    ██║██║    │
  │    ███████╗ ╚████╔╝ ███████╗█████╗██║ █╗ ██║██║    │
  │    ╚════██║  ╚██╔╝  ╚════██║╚════╝██║███╗██║╚═╝    │
  │    ███████║   ██║   ███████║       ███╔███╔╝██╗    │
  │    ╚══════╝   ╚═╝   ╚══════╝       ╚══╝╚══╝ ╚═╝    │
  │                                                     │
BANNER
    printf '%s' "$C_RESET$C_DIM"
    printf '  │  %-51s│\n' "Fedora DNF Manager v${SCRIPT_VERSION}  —  ${SCRIPT_AUTHOR}"
    [ "$DRY_RUN" -eq 1 ] && printf '  │  %-51s│\n' "⚠ DRY-RUN MODE — no changes will be made"
    printf '  └─────────────────────────────────────────────────────┘\n'
    printf '%s\n' "$C_RESET"
}

# Spinner — runs in background; caller kills PID stored in SPINNER_PID
_spinner_frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
spinner_start() {
    [ "$QUIET" -eq 1 ] && SPINNER_PID="" && return
    _msg="${1:-Working…}"
    (
        i=0
        while true; do
            _f=$(printf '%s' "$_spinner_frames" | cut -c$(( (i % 10) + 1 )))
            printf '\r  %s%s%s  %s  ' "$C_BCYAN" "$_f" "$C_RESET" "$_msg"
            sleep 0.08 2>/dev/null || sleep 1
            i=$(( i + 1 ))
        done
    ) &
    SPINNER_PID=$!
}

spinner_stop() {
    if [ -n "${SPINNER_PID:-}" ]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
        printf '\r\033[2K'   # clear spinner line
    fi
}

# =============================================================================
# SECTION 4 — CONFIG
# =============================================================================

# Defaults (overridable via conf file)
CFG_DEFAULT_YES=0
CFG_SHOW_CMD=1
CFG_CONFIRM_RISKY=1
CFG_AUTO_REFRESH=0
CFG_THEME=default     # reserved for future themes

load_config() {
    _ensure_dirs
    if [ ! -f "$CONF_FILE" ]; then
        write_default_config
    fi
    # shellcheck disable=SC1090
    . "$CONF_FILE" 2>/dev/null || true
    log_debug "Config loaded from $CONF_FILE"
}

write_default_config() {
    cat > "$CONF_FILE" <<'EOF'
# sys-wiz configuration
# Generated automatically — edit freely

# Skip confirmation prompts for non-destructive operations (0/1)
CFG_DEFAULT_YES=0

# Show the exact DNF command before executing (0/1)
CFG_SHOW_CMD=1

# Extra confirmation for risky operations (distro-sync, autoremove) (0/1)
CFG_CONFIRM_RISKY=1

# Automatically run dnf makecache on startup (0/1)
CFG_AUTO_REFRESH=0
EOF
    log_info "Wrote default config to $CONF_FILE"
}

# =============================================================================
# SECTION 5 — SIGNAL HANDLING & CLEANUP
# =============================================================================

_cleanup() {
    spinner_stop
    rm -f "$LOCK_FILE" 2>/dev/null || true
    tput cnorm 2>/dev/null || true  # restore cursor
    println ""
}

_sig_int() {
    println ""
    msg_warn "Interrupted by user."
    _cleanup
    exit 130
}

_sig_term() {
    msg_warn "Terminated."
    _cleanup
    exit 143
}

trap '_cleanup'   EXIT
trap '_sig_int'   INT
trap '_sig_term'  TERM

# Prevent concurrent instances
acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        _pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if kill -0 "$_pid" 2>/dev/null; then
            msg_error "Another instance of sys-wiz is running (PID $_pid)."
            exit 1
        fi
    fi
    echo $$ > "$LOCK_FILE"
}

# =============================================================================
# SECTION 6 — PREFLIGHT CHECKS
# =============================================================================

preflight() {
    # Fedora check
    if [ ! -f /etc/fedora-release ]; then
        msg_error "sys-wiz only supports Fedora Linux."
        msg_dim "Detected OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || echo unknown)"
        exit 1
    fi

    # Required tools
    for _cmd in dnf sudo rpm; do
        if ! command -v "$_cmd" >/dev/null 2>&1; then
            msg_error "Required command '$_cmd' not found in PATH."
            exit 1
        fi
    done

    # Collect system info
    FEDORA_VER=$(rpm -E %fedora 2>/dev/null || grep -oP '(?<=release )\d+' /etc/fedora-release 2>/dev/null || echo "?")
    DNF_VER=$(dnf --version 2>/dev/null | head -n1 || echo "unknown")

    # Network check (best-effort, non-fatal)
    if ! ping -c1 -W2 8.8.8.8 >/dev/null 2>&1 && \
       ! ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
        log_warn "Network appears offline."
        _NETWORK_WARN=1
    else
        _NETWORK_WARN=0
    fi

    log_info "Preflight OK — Fedora $FEDORA_VER, DNF $DNF_VER"
}

# =============================================================================
# SECTION 7 — SUDO MANAGEMENT
# =============================================================================

check_sudo() {
    section "Administrator Privileges"
    msg_info "sys-wiz needs elevated privileges to manage packages."
    msg_dim  "Your password is passed directly to sudo and never stored."
    print_nl
    if ! sudo -v 2>/dev/null; then
        msg_error "sudo authentication failed."
        log_error "sudo -v failed"
        exit 1
    fi
    msg_ok "Privileges confirmed."
    log_info "sudo authenticated"

    # Keep sudo alive in background
    (while true; do sudo -n true; sleep 55; done) &
    SUDO_KEEP_PID=$!
}

# =============================================================================
# SECTION 8 — COMMAND EXECUTION ENGINE
# =============================================================================

# execute_cmd CMD [EXPLANATION] [FLAGS]
#
# FLAGS (space-separated words in $3):
#   risky      — show extra warning, require explicit confirmation
#   readonly   — command does not modify the system (skip dry-run blocking)
#   nosudo     — run without sudo
#   noconfirm  — skip user confirmation (use for info-only commands)
#
execute_cmd() {
    _raw_cmd="$1"
    _explanation="${2:-No description provided.}"
    _flags="${3:-}"

    _is_risky=0;    _is_readonly=0; _nosudo=0; _noconfirm=0
    for _f in $_flags; do
        case "$_f" in
            risky)     _is_risky=1 ;;
            readonly)  _is_readonly=1 ;;
            nosudo)    _nosudo=1 ;;
            noconfirm) _noconfirm=1 ;;
        esac
    done

    # Build the final command string
    if [ "$_nosudo" -eq 1 ]; then
        _full_cmd="$_raw_cmd"
    else
        _full_cmd="sudo $_raw_cmd"
    fi

    print_nl
    hr "·"

    if [ "$CFG_SHOW_CMD" -eq 1 ]; then
        printf '  %sCommand:%s  %s%s%s\n' "$C_DIM" "$C_RESET" "$C_BOLD$C_BCYAN" "$_full_cmd" "$C_RESET"
    fi

    printf '  %sPurpose:%s  %s\n' "$C_DIM" "$C_RESET" "$_explanation"

    if [ "$_is_risky" -eq 1 ]; then
        print_nl
        printf '  %s%s WARNING %s  This operation may significantly alter your system.\n' \
            "$C_BOLD$C_BG_RED" "$C_WHITE" "$C_RESET"
    fi

    hr "·"

    # DRY-RUN: show command but don't execute
    if [ "$DRY_RUN" -eq 1 ] && [ "$_is_readonly" -eq 0 ]; then
        msg_dry "Would run: $_full_cmd"
        _log_cmd "[DRY-RUN] $_full_cmd"
        print_nl
        printf "  Press Enter to continue…"; read -r _
        return 0
    fi

    # ASSUME_YES: skip prompt for non-risky commands
    if [ "$_noconfirm" -eq 1 ] || \
       { [ "$ASSUME_YES" -eq 1 ] && [ "$_is_risky" -eq 0 ]; }; then
        _do_run=1
    else
        _do_run=0
        while true; do
            if [ "$_is_risky" -eq 1 ] && [ "$CFG_CONFIRM_RISKY" -eq 1 ]; then
                printf '  Type %sYES%s to confirm, or n to cancel: ' "$C_BOLD$C_BRED" "$C_RESET"
                read -r _ans
                case "$_ans" in
                    YES) _do_run=1; break ;;
                    [Nn]*|"") msg_info "Cancelled."; return 0 ;;
                    *) msg_warn "Type the word YES (uppercase) to confirm." ;;
                esac
            else
                printf '  %sProceed?%s [Y/n]: ' "$C_BOLD" "$C_RESET"
                read -r _ans
                case "$_ans" in
                    [Yy]*|"") _do_run=1; break ;;
                    [Nn]*)    msg_info "Cancelled."; return 0 ;;
                    *)        msg_warn "Please answer y or n." ;;
                esac
            fi
        done
    fi

    if [ "$_do_run" -eq 0 ]; then
        return 0
    fi

    print_nl
    hr "="
    log_info "Executing: $_full_cmd"
    _log_cmd "$_full_cmd"

    _start_ts=$(date +%s 2>/dev/null || echo 0)

    # Run the command — note: we unset -e so a dnf error doesn't kill the script
    set +e
    eval "$_full_cmd"
    _exit_code=$?
    set -e

    _end_ts=$(date +%s 2>/dev/null || echo 0)
    _elapsed=$(( _end_ts - _start_ts ))

    hr "="

    if [ "$_exit_code" -eq 0 ]; then
        msg_ok "Completed successfully (${_elapsed}s)"
        log_info "Success: $_full_cmd (${_elapsed}s)"

        # Record DNF transaction ID for rollback (if this was a dnf install/remove/upgrade)
        case "$_raw_cmd" in
            dnf\ install*|dnf\ remove*|dnf\ upgrade*|dnf\ reinstall*|dnf\ autoremove*)
                _txid=$(sudo dnf history 2>/dev/null | awk 'NR==2{print $1}' | tr -d ' |' || true)
                if [ -n "$_txid" ] && printf '%s' "$_txid" | grep -qE '^[0-9]+$'; then
                    _record_rollback "$_txid"
                fi
                ;;
        esac
    else
        msg_error "Command exited with code $_exit_code (${_elapsed}s)"
        log_error "Failed (exit $_exit_code): $_full_cmd"
        print_nl
        msg_dim "Tip: Check $LOG_FILE for details, or run with --verbose for more output."
    fi

    print_nl
    printf '  Press Enter to continue…'; read -r _
}

_record_rollback() {
    _id="$1"
    _ensure_dirs
    # Prepend new ID
    _tmp="${ROLLBACK_FILE}.tmp"
    echo "$_id" > "$_tmp"
    [ -f "$ROLLBACK_FILE" ] && head -n $(( MAX_ROLLBACK - 1 )) "$ROLLBACK_FILE" >> "$_tmp" || true
    mv "$_tmp" "$ROLLBACK_FILE"
    log_debug "Recorded rollback transaction ID: $_id"
}

# =============================================================================
# SECTION 9 — PACKAGE SELECTION HELPERS
# =============================================================================

# Prompt for a package name with completion hint
prompt_package() {
    print_nl
    printf '  %sPackage name%s (? to search first): ' "$C_BOLD" "$C_RESET"
    read -r _pkgname
    printf '%s' "$_pkgname"
}

# Interactive package search → returns chosen package name to stdout
search_and_select() {
    _query="$1"

    section "Package Search: $C_BCYAN$_query$C_RESET"
    spinner_start "Searching repositories…"
    set +e
    _results=$(dnf search "$_query" 2>/dev/null | grep -v "^Last metadata" | head -n "$SEARCH_LIMIT")
    set -e
    spinner_stop

    if [ -z "$_results" ]; then
        msg_warn "No results found for '$_query'."
        return 1
    fi

    println "$_results"
    print_nl
}

# =============================================================================
# SECTION 10 — INSTALL & REMOVE MENU
# =============================================================================

do_install() {
    section "Install Package"
    _pkg=$(prompt_package)
    [ -z "$_pkg" ] && msg_warn "No package entered." && return

    if [ "$_pkg" = "?" ]; then
        printf '  Search query: '; read -r _query
        search_and_select "$_query" || return
        printf '  Package to install: '; read -r _pkg
        [ -z "$_pkg" ] && return
    else
        # Quick search preview
        spinner_start "Checking '$_pkg'…"
        set +e
        _info=$(dnf info "$_pkg" 2>/dev/null | grep -E "^(Name|Version|Summary|Size)" | head -8)
        set -e
        spinner_stop
        if [ -n "$_info" ]; then
            print_nl
            println "$_info" | while IFS= read -r _line; do msg_dim "  $_line"; done
            print_nl
        fi
    fi

    execute_cmd "dnf install -y $_pkg" \
        "Install '$_pkg' and any required dependencies."
}

do_remove() {
    section "Remove Package"
    _pkg=$(prompt_package)
    [ -z "$_pkg" ] && msg_warn "No package entered." && return

    # Check if installed
    spinner_start "Checking installation status…"
    set +e
    _installed=$(dnf list installed "$_pkg" 2>/dev/null | grep -v "^Installed" | head -5)
    set -e
    spinner_stop

    if [ -z "$_installed" ]; then
        msg_warn "Package '$_pkg' does not appear to be installed."
        printf '  Continue anyway? [y/N]: '; read -r _ans
        case "$_ans" in [Yy]*) ;; *) return ;; esac
    else
        print_nl
        println "$_installed" | while IFS= read -r _l; do msg_dim "  $_l"; done
        print_nl
    fi

    execute_cmd "dnf remove -y $_pkg" \
        "Remove '$_pkg' and any packages that solely depended on it." \
        "risky"
}

do_reinstall() {
    section "Reinstall Package"
    _pkg=$(prompt_package)
    [ -z "$_pkg" ] && msg_warn "No package entered." && return

    spinner_start "Verifying package is installed…"
    set +e
    _ok=$(dnf list installed "$_pkg" 2>/dev/null | grep -v "^Installed")
    set -e
    spinner_stop

    if [ -z "$_ok" ]; then
        msg_warn "'$_pkg' is not installed — cannot reinstall."
        return
    fi

    execute_cmd "dnf reinstall -y $_pkg" \
        "Reinstall '$_pkg' from the current repository version (useful for repairing corrupted files)."
}

do_downgrade() {
    section "Downgrade Package"
    msg_warn "Downgrading can cause dependency conflicts. Use with care."
    _pkg=$(prompt_package)
    [ -z "$_pkg" ] && return

    spinner_start "Fetching available versions…"
    set +e
    _versions=$(dnf --showduplicates list "$_pkg" 2>/dev/null | tail -n +3 | head -20)
    set -e
    spinner_stop

    if [ -n "$_versions" ]; then
        section "Available versions of $_pkg"
        println "$_versions"
        print_nl
    fi

    execute_cmd "dnf downgrade $_pkg" \
        "Downgrade '$_pkg' to the previous available version." \
        "risky"
}

do_info() {
    section "Package Info"
    _pkg=$(prompt_package)
    [ -z "$_pkg" ] && return

    execute_cmd "dnf info $_pkg" \
        "Display detailed metadata for '$_pkg'." \
        "readonly noconfirm nosudo"
}

do_files() {
    section "Files Owned by Package"
    _pkg=$(prompt_package)
    [ -z "$_pkg" ] && return

    execute_cmd "rpm -ql $_pkg" \
        "List all files installed by package '$_pkg'." \
        "readonly noconfirm nosudo"
}

do_which_pkg() {
    section "Which Package Owns a File"
    print_nl
    printf '  File path: '; read -r _filepath
    [ -z "$_filepath" ] && return

    execute_cmd "rpm -qf $_filepath" \
        "Find which package owns the file '$_filepath'." \
        "readonly noconfirm nosudo"
}

menu_install_remove() {
    while true; do
        section "Install & Remove"
        _menu_opts \
            "1" "Install package" \
            "2" "Remove package" \
            "3" "Reinstall package" \
            "4" "Downgrade package" \
            "5" "Package info / details" \
            "6" "List files owned by package" \
            "7" "Find package that owns a file" \
            "0" "← Back"

        _read_choice 0 7
        case "$MENU_CHOICE" in
            1) do_install ;;
            2) do_remove ;;
            3) do_reinstall ;;
            4) do_downgrade ;;
            5) do_info ;;
            6) do_files ;;
            7) do_which_pkg ;;
            0) return ;;
        esac
    done
}

# =============================================================================
# SECTION 11 — SYSTEM MAINTENANCE MENU
# =============================================================================

do_update() {
    section "System Update"
    [ "$_NETWORK_WARN" -eq 1 ] && msg_warn "Network may be offline — update might fail."

    execute_cmd "dnf upgrade -y" \
        "Upgrade all installed packages to their latest available versions."
}

do_update_refresh() {
    section "System Update (Force Refresh)"
    [ "$_NETWORK_WARN" -eq 1 ] && msg_warn "Network may be offline."

    execute_cmd "dnf upgrade -y --refresh" \
        "Force-refresh repository metadata, then upgrade all packages."
}

do_update_security() {
    section "Security-Only Update"
    execute_cmd "dnf upgrade -y --security" \
        "Apply only packages marked as security fixes."
}

do_list_orphans() {
    section "Orphaned Packages"
    execute_cmd "dnf list extras" \
        "List installed packages not available in any enabled repository." \
        "readonly noconfirm nosudo"
}

do_autoremove() {
    section "Remove Orphaned Packages"
    msg_info "Previewing packages that would be removed…"
    print_nl
    set +e
    sudo dnf autoremove --assumeno 2>/dev/null | tail -n +2 | head -30
    set -e
    print_nl

    execute_cmd "dnf autoremove -y" \
        "Remove all packages no longer required as dependencies." \
        "risky"
}

do_check_deps() {
    section "Dependency Check"
    execute_cmd "dnf repoquery --unsatisfied" \
        "Report any packages with unsatisfied dependencies." \
        "readonly noconfirm nosudo"
}

do_check_update_list() {
    section "Available Updates"
    execute_cmd "dnf check-update" \
        "List packages that have newer versions available (exit 100 = updates exist, 0 = up to date)." \
        "readonly noconfirm nosudo"
}

do_fix_db() {
    section "Repair RPM Database"
    msg_warn "This rebuilds the RPM database. Only needed after corruption."
    execute_cmd "rpm --rebuilddb" \
        "Rebuild the RPM package database from scratch." \
        "risky"
}

menu_maintenance() {
    while true; do
        section "System Maintenance"
        _menu_opts \
            "1" "Upgrade all packages" \
            "2" "Upgrade (force metadata refresh)" \
            "3" "Security-only upgrade" \
            "4" "List available updates" \
            "5" "List orphaned packages" \
            "6" "Remove orphaned packages" \
            "7" "Check dependency integrity" \
            "8" "Repair RPM database" \
            "0" "← Back"

        _read_choice 0 8
        case "$MENU_CHOICE" in
            1) do_update ;;
            2) do_update_refresh ;;
            3) do_update_security ;;
            4) do_check_update_list ;;
            5) do_list_orphans ;;
            6) do_autoremove ;;
            7) do_check_deps ;;
            8) do_fix_db ;;
            0) return ;;
        esac
    done
}

# =============================================================================
# SECTION 12 — INFORMATION MENU
# =============================================================================

do_list_installed() {
    section "Installed Packages"
    printf '  Filter (leave blank for all): '; read -r _filter
    if [ -n "$_filter" ]; then
        execute_cmd "dnf list installed | grep -i '$_filter'" \
            "List installed packages matching '$_filter'." \
            "readonly noconfirm nosudo"
    else
        execute_cmd "dnf list installed | less" \
            "List all installed packages (piped through less)." \
            "readonly noconfirm nosudo"
    fi
}

do_history() {
    section "DNF Transaction History"
    execute_cmd "dnf history" \
        "Show all recorded DNF transactions." \
        "readonly noconfirm nosudo"
}

do_history_info() {
    section "Transaction Detail"
    print_nl
    printf '  Transaction ID (blank = last): '; read -r _tid
    _tid="${_tid:-last}"
    execute_cmd "dnf history info $_tid" \
        "Show detailed info for DNF transaction #$_tid." \
        "readonly noconfirm nosudo"
}

do_repolist() {
    section "Enabled Repositories"
    execute_cmd "dnf repolist enabled" \
        "List all currently enabled DNF repositories." \
        "readonly noconfirm nosudo"
}

do_repolist_all() {
    section "All Repositories"
    execute_cmd "dnf repolist all" \
        "List all repositories, both enabled and disabled." \
        "readonly noconfirm nosudo"
}

do_sys_wiz_history() {
    section "sys-wiz Command History"
    if [ ! -f "$HIST_FILE" ]; then
        msg_info "No history yet."
        print_nl; printf '  Press Enter…'; read -r _; return
    fi
    print_nl
    cat "$HIST_FILE" | tail -50
    print_nl; printf '  Press Enter…'; read -r _
}

menu_information() {
    while true; do
        section "Information & History"
        _menu_opts \
            "1" "List installed packages" \
            "2" "Available updates" \
            "3" "DNF transaction history" \
            "4" "DNF transaction detail" \
            "5" "Enabled repositories" \
            "6" "All repositories" \
            "7" "sys-wiz command history" \
            "0" "← Back"

        _read_choice 0 7
        case "$MENU_CHOICE" in
            1) do_list_installed ;;
            2) do_check_update_list ;;
            3) do_history ;;
            4) do_history_info ;;
            5) do_repolist ;;
            6) do_repolist_all ;;
            7) do_sys_wiz_history ;;
            0) return ;;
        esac
    done
}

# =============================================================================
# SECTION 13 — REPOSITORY MENU
# =============================================================================

do_enable_rpmfusion_free() {
    section "Enable RPM Fusion Free"
    msg_info "RPM Fusion provides software excluded from official Fedora repos."
    msg_dim  "Free = open-source software, licence-compatible with Fedora policy."
    print_nl
    execute_cmd "dnf install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
        "Enable the RPM Fusion Free repository for Fedora $FEDORA_VER."
}

do_enable_rpmfusion_nonfree() {
    section "Enable RPM Fusion Non-Free"
    msg_warn "Non-free = proprietary or patent-encumbered software."
    print_nl
    execute_cmd "dnf install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm" \
        "Enable the RPM Fusion Non-Free repository for Fedora $FEDORA_VER." \
        "risky"
}

do_enable_flathub() {
    section "Enable Flathub (Flatpak)"
    if ! command -v flatpak >/dev/null 2>&1; then
        msg_warn "flatpak is not installed. Installing it first…"
        execute_cmd "dnf install -y flatpak" "Install Flatpak runtime."
    fi
    execute_cmd "flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo" \
        "Add the Flathub repository as a Flatpak remote." \
        "nosudo"
}

do_enable_copr() {
    section "Enable COPR Repository"
    msg_warn "COPR repos are community-maintained. Trust carefully."
    print_nl
    printf '  COPR repo (format: user/repo): '; read -r _copr
    [ -z "$_copr" ] && return
    execute_cmd "dnf copr enable -y $_copr" \
        "Enable COPR repository '$_copr'." \
        "risky"
}

do_disable_repo() {
    section "Disable Repository"
    do_repolist
    print_nl
    printf '  Repository ID to disable: '; read -r _repo
    [ -z "$_repo" ] && return
    execute_cmd "dnf config-manager --set-disabled $_repo" \
        "Disable repository '$_repo' (does not uninstall packages)." \
        "risky"
}

do_enable_repo() {
    section "Enable Repository"
    do_repolist_all
    print_nl
    printf '  Repository ID to enable: '; read -r _repo
    [ -z "$_repo" ] && return
    execute_cmd "dnf config-manager --set-enabled $_repo" \
        "Enable repository '$_repo'."
}

do_refresh_metadata() {
    section "Refresh Repository Metadata"
    execute_cmd "dnf makecache" \
        "Download and cache the latest repository metadata."
}

menu_repositories() {
    while true; do
        section "Repositories"
        _menu_opts \
            "1" "Refresh metadata cache" \
            "2" "Enable RPM Fusion (free)" \
            "3" "Enable RPM Fusion (non-free)" \
            "4" "Enable Flathub (Flatpak)" \
            "5" "Enable COPR repository" \
            "6" "Enable a disabled repository" \
            "7" "Disable a repository" \
            "0" "← Back"

        _read_choice 0 7
        case "$MENU_CHOICE" in
            1) do_refresh_metadata ;;
            2) do_enable_rpmfusion_free ;;
            3) do_enable_rpmfusion_nonfree ;;
            4) do_enable_flathub ;;
            5) do_enable_copr ;;
            6) do_enable_repo ;;
            7) do_disable_repo ;;
            0) return ;;
        esac
    done
}

# =============================================================================
# SECTION 14 — ADVANCED / ROLLBACK MENU
# =============================================================================

do_distro_sync() {
    section "distro-sync"
    msg_warn "distro-sync aligns all packages to the exact versions in enabled repos."
    msg_warn "This may DOWNGRADE packages. It is the most aggressive update operation."
    print_nl
    execute_cmd "dnf distro-sync -y" \
        "Synchronize all installed packages to current repository state (may downgrade)." \
        "risky"
}

do_clean_cache() {
    section "Clean DNF Cache"
    execute_cmd "dnf clean all" \
        "Remove all cached metadata and downloaded packages."
}

do_rollback() {
    section "Rollback Last Transaction"
    if [ ! -f "$ROLLBACK_FILE" ] || [ ! -s "$ROLLBACK_FILE" ]; then
        msg_warn "No rollback history recorded by sys-wiz yet."
        print_nl; printf '  Press Enter…'; read -r _; return
    fi

    msg_info "Last recorded transactions (newest first):"
    print_nl
    _i=1
    while IFS= read -r _tid; do
        printf '  %s%d)%s  Transaction #%s\n' "$C_BOLD" "$_i" "$C_RESET" "$_tid"
        sudo dnf history info "$_tid" 2>/dev/null | grep -E "^(Action|Package)" | head -5 | \
            while IFS= read -r _l; do msg_dim "       $_l"; done
        print_nl
        _i=$(( _i + 1 ))
    done < "$ROLLBACK_FILE"

    printf '  Transaction ID to undo (or Enter to cancel): '; read -r _tid
    [ -z "$_tid" ] && return

    execute_cmd "dnf history undo $_tid" \
        "Undo DNF transaction #$_tid (reverses installs/removes from that transaction)." \
        "risky"
}

do_replay() {
    section "Replay Transaction"
    print_nl
    printf '  Transaction ID to replay: '; read -r _tid
    [ -z "$_tid" ] && return

    execute_cmd "dnf history replay $_tid" \
        "Re-apply DNF transaction #$_tid." \
        "risky"
}

do_mark_manual() {
    section "Mark Package as Manually Installed"
    _pkg=$(prompt_package)
    [ -z "$_pkg" ] && return
    execute_cmd "dnf mark install $_pkg" \
        "Mark '$_pkg' as a manually installed package (prevents autoremove)."
}

do_mark_dep() {
    section "Mark Package as Dependency"
    _pkg=$(prompt_package)
    [ -z "$_pkg" ] && return
    execute_cmd "dnf mark remove $_pkg" \
        "Mark '$_pkg' as a dependency (eligible for autoremove if no dependents)." \
        "risky"
}

do_shell() {
    section "DNF Shell (Interactive)"
    msg_info "Launches the dnf interactive shell for bulk operations."
    msg_dim  "Type 'exit' to return to sys-wiz."
    print_nl
    execute_cmd "dnf shell" \
        "Open the DNF interactive shell." \
        "risky"
}

menu_advanced() {
    while true; do
        section "Advanced Operations"
        _menu_opts \
            "1" "distro-sync (match repos exactly)" \
            "2" "Clean DNF cache" \
            "3" "Rollback a transaction" \
            "4" "Replay a transaction" \
            "5" "Mark package as manually installed" \
            "6" "Mark package as dependency" \
            "7" "Open DNF interactive shell" \
            "0" "← Back"

        _read_choice 0 7
        case "$MENU_CHOICE" in
            1) do_distro_sync ;;
            2) do_clean_cache ;;
            3) do_rollback ;;
            4) do_replay ;;
            5) do_mark_manual ;;
            6) do_mark_dep ;;
            7) do_shell ;;
            0) return ;;
        esac
    done
}

# =============================================================================
# SECTION 15 — SETTINGS MENU
# =============================================================================

menu_settings() {
    while true; do
        section "Settings"
        _yn() { [ "$1" -eq 1 ] && printf '%sON%s' "$C_BGREEN" "$C_RESET" || printf '%sOFF%s' "$C_DIM" "$C_RESET"; }

        _menu_opts \
            "1" "Toggle dry-run mode         [$( _yn $DRY_RUN)]" \
            "2" "Toggle verbose logging      [$( _yn $VERBOSE)]" \
            "3" "Toggle show commands        [$( _yn $CFG_SHOW_CMD)]" \
            "4" "Toggle risky confirmation   [$( _yn $CFG_CONFIRM_RISKY)]" \
            "5" "View log file" \
            "6" "Open config in \$EDITOR" \
            "7" "Reset config to defaults" \
            "0" "← Back"

        _read_choice 0 7
        case "$MENU_CHOICE" in
            1) DRY_RUN=$(( 1 - DRY_RUN ))
               [ "$DRY_RUN" -eq 1 ] && msg_ok "Dry-run ON — commands will be previewed only." \
                                     || msg_ok "Dry-run OFF — commands will execute normally." ;;
            2) VERBOSE=$(( 1 - VERBOSE ))
               msg_ok "Verbose $( [ "$VERBOSE" -eq 1 ] && echo ON || echo OFF )" ;;
            3) CFG_SHOW_CMD=$(( 1 - CFG_SHOW_CMD ))
               msg_ok "Show commands $( [ "$CFG_SHOW_CMD" -eq 1 ] && echo ON || echo OFF )" ;;
            4) CFG_CONFIRM_RISKY=$(( 1 - CFG_CONFIRM_RISKY ))
               msg_ok "Risky confirmation $( [ "$CFG_CONFIRM_RISKY" -eq 1 ] && echo ON || echo OFF )" ;;
            5) [ -f "$LOG_FILE" ] && less "$LOG_FILE" || msg_warn "No log file yet." ;;
            6) _ed="${EDITOR:-vi}"
               "$_ed" "$CONF_FILE"
               load_config ;;
            7) write_default_config && load_config && msg_ok "Config reset." ;;
            0) return ;;
        esac
    done
}

# =============================================================================
# SECTION 16 — PLUGINS
# =============================================================================

load_plugins() {
    _ensure_dirs
    _count=0
    if [ -d "$PLUGIN_DIR" ]; then
        for _pf in "$PLUGIN_DIR"/*.plugin; do
            [ -f "$_pf" ] || continue
            # shellcheck disable=SC1090
            . "$_pf" 2>/dev/null && _count=$(( _count + 1 )) \
                && log_info "Loaded plugin: $_pf" \
                || log_warn "Plugin failed to load: $_pf"
        done
    fi
    log_debug "$_count plugin(s) loaded"
}

# =============================================================================
# SECTION 17 — MENU ENGINE (text-based, no whiptail required)
# =============================================================================

# _menu_opts takes pairs: "key" "label" ...
_menu_opts() {
    print_nl
    while [ "$#" -ge 2 ]; do
        _key="$1"; _lbl="$2"; shift 2
        if [ "$_key" = "0" ]; then
            printf '  %s  0)%s  %s\n' "$C_DIM" "$C_RESET" "$_lbl"
        else
            printf '  %s%s)%s  %s\n' "$C_BOLD$C_BCYAN" "$_key" "$C_RESET" "$_lbl"
        fi
    done
    print_nl
}

MENU_CHOICE=""
_read_choice() {
    _min="${1:-0}"; _max="${2:-9}"
    while true; do
        printf '  %sChoice [%d-%d]:%s ' "$C_DIM" "$_min" "$_max" "$C_RESET"
        read -r MENU_CHOICE
        # Validate it's a number in range
        case "$MENU_CHOICE" in
            ''|*[!0-9]*) msg_warn "Enter a number between $_min and $_max." ;;
            *)
                if [ "$MENU_CHOICE" -ge "$_min" ] && [ "$MENU_CHOICE" -le "$_max" ]; then
                    return
                else
                    msg_warn "Enter a number between $_min and $_max."
                fi
                ;;
        esac
    done
}

# =============================================================================
# SECTION 18 — STARTUP SCREEN
# =============================================================================

startup_screen() {
    banner

    # System info panel
    _net_status="${C_BGREEN}online${C_RESET}"
    [ "${_NETWORK_WARN:-0}" -eq 1 ] && _net_status="${C_BRED}possibly offline${C_RESET}"

    printf '  %s%-18s%s %s\n'   "$C_DIM" "Fedora:"     "$C_RESET"  "Fedora $FEDORA_VER"
    printf '  %s%-18s%s %s\n'   "$C_DIM" "DNF:"        "$C_RESET"  "$DNF_VER"
    printf '  %s%-18s%s '       "$C_DIM" "Network:"    "$C_RESET"
    printf '%b\n' "$_net_status"
    printf '  %s%-18s%s %s\n'   "$C_DIM" "Config:"     "$C_RESET"  "$CONF_FILE"
    printf '  %s%-18s%s %s\n'   "$C_DIM" "Log:"        "$C_RESET"  "$LOG_FILE"
    [ "$DRY_RUN" -eq 1 ] && printf '  %s%-18s%s %s\n' "$C_BYELLOW" "Mode:" "$C_RESET" "DRY-RUN (no changes made)"

    print_nl
    printf '  Press Enter to continue…'; read -r _
}

# =============================================================================
# SECTION 19 — CLI ARGUMENT PARSING
# =============================================================================

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -n|--dry-run)    DRY_RUN=1 ;;
            -v|--verbose)    VERBOSE=1 ;;
            -y|--yes)        ASSUME_YES=1 ;;
            -q|--quiet)      QUIET=1 ;;
            -b|--batch)      BATCH_MODE=1; ASSUME_YES=1; QUIET=1 ;;
            --no-color)      # colours already empty; don't init
                             ;;
            --version)
                printf '%s version %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"
                exit 0
                ;;
            --help|-h)
                print_help
                exit 0
                ;;
            --)              shift; break ;;
            -*)
                printf 'Unknown option: %s\n' "$1" >&2
                exit 1
                ;;
            *)               break ;;
        esac
        shift
    done
}

print_help() {
    cat <<EOF
$SCRIPT_NAME $SCRIPT_VERSION — Guided Fedora DNF manager

USAGE
  sys-wiz [OPTIONS]

OPTIONS
  -n, --dry-run     Preview commands; never execute any
  -v, --verbose     Extra debug logging
  -y, --yes         Skip confirmations (except risky operations)
  -q, --quiet       Suppress spinner and progress noise
  -b, --batch       Non-interactive mode (implies -y -q)
  --no-color        Disable ANSI colours
  --version         Print version and exit
  -h, --help        This help text

FILES
  Config:   $CONF_FILE
  Log:      $LOG_FILE
  History:  $HIST_FILE
  Plugins:  $PLUGIN_DIR/*.plugin

PLUGINS
  Drop any *.plugin shell file into the plugins directory.
  Each plugin can define new menu functions and register them
  with the PLUGIN_MENU_ENTRIES variable.

EOF
}

# =============================================================================
# SECTION 20 — MAIN MENU & ENTRY POINT
# =============================================================================

main_menu() {
    while true; do
        banner

        # Dynamic header line
        printf '  %s%s%s   Fedora %s   DNF %s\n' \
            "$C_DIM" "$(date '+%a %d %b %Y  %H:%M')" "$C_RESET" \
            "$FEDORA_VER" "$DNF_VER"
        print_nl

        _menu_opts \
            "1" "System Maintenance   — upgrade, clean, check" \
            "2" "Install & Remove     — search, install, remove, downgrade" \
            "3" "Information          — lists, history, repos" \
            "4" "Repositories         — RPM Fusion, Flathub, COPR, toggle" \
            "5" "Advanced             — distro-sync, rollback, DNF shell" \
            "6" "Settings             — dry-run, verbosity, config" \
            "0" "Exit"

        _read_choice 0 6
        case "$MENU_CHOICE" in
            1) menu_maintenance ;;
            2) menu_install_remove ;;
            3) menu_information ;;
            4) menu_repositories ;;
            5) menu_advanced ;;
            6) menu_settings ;;
            0) break ;;
        esac
    done
}

main() {
    setup_terminal
    parse_args "$@"
    _ensure_dirs
    load_config
    load_plugins
    acquire_lock

    log_info "=== sys-wiz $SCRIPT_VERSION started (PID $$) ==="

    preflight

    if [ "$BATCH_MODE" -eq 0 ]; then
        startup_screen
        check_sudo

        if [ "${CFG_AUTO_REFRESH:-0}" -eq 1 ]; then
            msg_step "Auto-refreshing repository metadata…"
            set +e; sudo dnf makecache -q 2>/dev/null; set -e
        fi

        main_menu
    fi

    println ""
    msg_ok "Session complete. Goodbye."
    log_info "=== sys-wiz exited cleanly ==="
    println ""
}

main "$@"
