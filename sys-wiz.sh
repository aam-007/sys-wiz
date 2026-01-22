#!/bin/bash

# ==============================================================================
# sys-wiz
# Version: 1.1.1 (Fixed privilege escalation)
#
# A minimalist, safety-first terminal wizard for DNF on Fedora Linux.
# ==============================================================================

# --- Safety Flags ---
set -u
set -o pipefail

# --- Configuration & Constants ---
APP_TITLE="sys-wiz"
APP_VERSION="1.1.1"
APP_AUTHOR="Aditya Mishra (github.com/aam-007)"
APP_REPO="github.com/aam-007/sys-wiz"
TEMP_FILE=$(mktemp)

# Risk Levels
RISK_INFO="INFO"       # Read-only
RISK_NORMAL="NORMAL"   # Standard install/update
RISK_HIGH="HIGH"       # Removal, Repository changes
RISK_CRITICAL="CRITICAL" # Distro-sync, History Undo

# UI Defaults (Conservative defaults for 80x24 terminals)
H=18
W=74
M=10 # Menu height

# --- Trap Cleanup ---
cleanup() {
    rm -f "$TEMP_FILE"
}
trap cleanup EXIT SIGINT SIGTERM

# --- Dependency & Environment Checks ---

if command -v whiptail >/dev/null; then
    UI_BIN="whiptail"
elif command -v dialog >/dev/null; then
    UI_BIN="dialog"
else
    echo "Error: Missing dependency."
    echo "This tool requires 'newt' (whiptail) or 'dialog'."
    echo "To fix, run: sudo dnf install newt"
    exit 1
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "${ID:-}" != "fedora" ]; then
        echo "Error: Detected OS is '${ID:-unknown}'."
        echo "sys-wiz is designed strictly for Fedora Linux."
        exit 1
    fi
    FEDORA_VERSION="${VERSION_ID:-}"
else
    echo "Error: /etc/os-release missing. Cannot verify OS."
    exit 1
fi

if ! command -v dnf >/dev/null; then
    echo "Error: 'dnf' binary not found."
    exit 1
fi
DNF_VERSION=$(dnf --version | head -n 1 | awk '{print $1 " " $2}')

HAS_PLUGINS=0
if rpm -q dnf-plugins-core >/dev/null 2>&1; then
    HAS_PLUGINS=1
fi

# --- Helper Functions ---

show_msg() {
    $UI_BIN --title "$APP_TITLE" --msgbox "$1" 10 60
}

validate_input() {
    local input="$1"
    local type="$2"

    if [ -z "$input" ]; then return 1; fi

    case "$type" in
        package|module)
            [[ "$input" =~ ^[a-zA-Z0-9._+:-]+$ ]]
            ;;
        id)
            [[ "$input" =~ ^[a-zA-Z0-9._-]+$ ]]
            ;;
        path)
            [ -f "$input" ]
            ;;
        *)
            return 1
            ;;
    esac
}

exec_dnf() {
    local subcmd="$1"
    local description="$2"
    local exit_mode="$3"
    shift 3
    local dnf_args=("$@")

    local cmd_display="dnf ${dnf_args[*]}"
    local risk="$RISK_INFO"

    case "$subcmd" in
        check-update|search|provides|list|info|history|repolist|check)
            risk="$RISK_INFO" ;;
        install|upgrade|reinstall|module|clean)
            risk="$RISK_NORMAL" ;;
        remove|config-manager)
            risk="$RISK_HIGH" ;;
        autoremove|distro-sync|history-undo)
            risk="$RISK_CRITICAL" ;;
        *)
            risk="$RISK_NORMAL" ;;
    esac

    local title prompt_text
    case "$risk" in
        INFO)
            title="Execute Query"
            prompt_text="Command:\n  $cmd_display\n\nContext:\n$description\n\nRun this query?"
            ;;
        NORMAL)
            title="Confirm Operation"
            prompt_text="You are about to modify the system.\n\nCommand:\n  $cmd_display\n\nExplanation:\n$description\n\nProceed?"
            ;;
        HIGH)
            title="WARNING: High Risk"
            prompt_text="WARNING: This action changes configuration or removes software.\n\nCommand:\n  $cmd_display\n\nExplanation:\n$description\n\nAre you sure?"
            ;;
        CRITICAL)
            title="DANGER: Destructive Operation"
            prompt_text="CRITICAL WARNING: This operation can significantly alter your system state or remove data.\n\nCommand:\n  $cmd_display\n\nExplanation:\n$description\n\nProceed only if you understand the consequences."
            ;;
    esac

    if $UI_BIN --title "$title" --defaultno --yesno "$prompt_text" 16 74; then
        clear
        echo "----------------------------------------------------------------"
        echo " timestamp : $(date '+%Y-%m-%d %H:%M:%S')"
        echo " command   : dnf ${dnf_args[*]}"
        echo " intent    : $description"
        echo "----------------------------------------------------------------"

        sudo dnf "${dnf_args[@]}"
        local ret=$?

        echo "----------------------------------------------------------------"
        case "$exit_mode:$ret" in
            signal-100-ok:100) echo "Result: UPDATES AVAILABLE" ;;
            *:0) echo "Result: SUCCESS" ;;
            *) echo "Result: FAILED (Exit Code: $ret)" ;;
        esac
        echo "----------------------------------------------------------------"
        read -r
    else
        show_msg "Action cancelled."
    fi
}

get_input_text() {
    $UI_BIN --title "$1" --inputbox "$2" 10 60 2> "$TEMP_FILE"
    [ $? -eq 0 ] && cat "$TEMP_FILE" || echo ""
}

# --- Functional Stages ---

stage_launch() {
    clear
    echo "sys-wiz v$APP_VERSION"
    echo "Author: $APP_AUTHOR"
    echo "Repo: $APP_REPO"
    echo "========================================"
    echo "Fedora $FEDORA_VERSION | $DNF_VERSION"
    echo "----------------------------------------"
    echo "Guided, transparent DNF package manager."
    echo ""
    if [ "$HAS_PLUGINS" -eq 0 ]; then
        echo "WARNING: 'dnf-plugins-core' is missing."
        echo "          Repository management features will be disabled."
        echo ""
    fi
    read -r
}

stage_privileges() {
    if [ "$(id -u)" -ne 0 ]; then
        clear
        echo "Authorization Required"
        echo "----------------------"
        echo "This tool modifies system state and requires root privileges."
        echo "Restarting with sudo..."
        echo ""
        
        # Wait a moment for user to read
        sleep 1
        
        # Re-execute script with sudo, preserving terminal I/O
        if [ -t 0 ] && [ -t 1 ] && [ -t 2 ]; then
            # We're in a terminal, use exec with proper redirection
            exec sudo --preserve-env=PATH -E bash "$0" "$@" 0<&0 1>&1 2>&2
        else
            # Fallback for non-terminal environments
            exec sudo --preserve-env=PATH -E bash "$0" "$@"
        fi
        
        # If we get here, exec failed
        echo "Error: Failed to elevate privileges."
        exit 1
    fi
    
    # Verify sudo is still valid
    sudo -v 2>/dev/null || {
        echo "Error: sudo authentication failed or timed out."
        exit 1
    }
}

# --- Menus ---

menu_help() {
    local help_text="sys-wiz Help

Purpose:
A strictly guided wrapper for DNF to prevent user error.

Risk Levels:
[INFO]     - Read only. Safe.
[NORMAL]   - Installs/Updates. Low risk.
[HIGH]     - Removals/Repo changes. Pay attention.
[CRITICAL] - System syncs/Rollbacks. Dangerous.

Controls:
Arrow Keys - Navigate
Enter      - Select
Esc        - Back/Cancel

No actions are taken without your explicit confirmation."

    $UI_BIN --title "Help" --msgbox "$help_text" 20 70
}

menu_maintenance() {
    while true; do
        $UI_BIN --title "System Health & Maintenance" --menu "Select Task:" $H $W $M \
            "1" "Check for updates (Dry run)" \
            "2" "Update system (Standard)" \
            "3" "Update system (Refresh metadata)" \
            "4" "Check system health (Dependencies)" \
            "5" "Clean up orphaned packages" \
            "6" "Disk Usage: Clean all caches" \
            "0" "Back" 2> "$TEMP_FILE"

        case $(cat "$TEMP_FILE") in
            1) exec_dnf "check-update" "Checks for available updates without installing them." "signal-100-ok" "check-update" ;;
            2) exec_dnf "upgrade" "Upgrades all installed packages to the latest version." "default" "upgrade" ;;
            3) exec_dnf "upgrade" "Refreshes repository metadata, then upgrades system." "default" "upgrade" "--refresh" ;;
            4) exec_dnf "check" "Checks local RPM database for broken dependencies." "default" "check" ;;
            5) exec_dnf "autoremove" "Removes packages no longer needed by any installed software." "default" "autoremove" ;;
            6) exec_dnf "clean" "Removes all cached package data. Frees disk space but slows next update." "default" "clean" "all" ;;
            0|*) break ;;
        esac
    done
}

menu_packages() {
    while true; do
        $UI_BIN --title "Package Management" --menu "Select Action:" $H $W $M \
            "1" "Search (Name/Desc)" \
            "2" "Find provider (What provides file?)" \
            "3" "Install package" \
            "4" "Install local RPM file" \
            "5" "Remove package" \
            "6" "Reinstall package" \
            "0" "Back" 2> "$TEMP_FILE"

        local sel=$(cat "$TEMP_FILE")
        case $sel in
            1)
                term=$(get_input_text "Search" "Enter search keyword:")
                if validate_input "$term" "package"; then
                    exec_dnf "search" "Searches repository metadata." "default" "search" "$term"
                else
                    [ -n "$term" ] && show_msg "Invalid input. Alphanumeric only."
                fi
                ;;
            2)
                file=$(get_input_text "Identify Provider" "Enter file name or path (e.g., /usr/bin/ls):")
                if [ -n "$file" ]; then # relaxed validation for paths/files
                    exec_dnf "provides" "Finds which package owns the specified file." "default" "provides" "$file"
                fi
                ;;
            3)
                pkg=$(get_input_text "Install" "Enter package name:")
                if validate_input "$pkg" "package"; then
                    exec_dnf "install" "Installs '$pkg' and dependencies." "default" "install" "$pkg"
                elif [ -n "$pkg" ]; then
                    show_msg "Invalid package name."
                fi
                ;;
            4)
                path=$(get_input_text "Local Install" "Enter absolute path to .rpm file:")
                if validate_input "$path" "path"; then
                    exec_dnf "install" "Installs local RPM file using DNF (resolves deps)." "default" "install" "$path"
                elif [ -n "$path" ]; then
                    show_msg "File not found or invalid path."
                fi
                ;;
            5)
                pkg=$(get_input_text "Remove" "Enter package name:")
                if validate_input "$pkg" "package"; then
                    exec_dnf "remove" "Removes '$pkg'. Review list of dependents carefully!" "default" "remove" "$pkg"
                fi
                ;;
            6)
                pkg=$(get_input_text "Reinstall" "Enter package name:")
                if validate_input "$pkg" "package"; then
                    exec_dnf "reinstall" "Reinstalls current version of '$pkg'." "default" "reinstall" "$pkg"
                fi
                ;;
            0|*) break ;;
        esac
    done
}

menu_info() {
    while true; do
        $UI_BIN --title "Information & History" --menu "Select View:" $H $W $M \
            "1" "List installed packages" \
            "2" "Package details (Info)" \
            "3" "View Transaction History" \
            "4" "View Specific Transaction Details" \
            "0" "Back" 2> "$TEMP_FILE"

        case $(cat "$TEMP_FILE") in
            1) exec_dnf "list" "Lists all installed packages." "default" "list" "installed" ;;
            2) 
                pkg=$(get_input_text "Package Info" "Enter package name:")
                if validate_input "$pkg" "package"; then
                    exec_dnf "info" "Displays metadata for '$pkg'." "default" "info" "$pkg"
                fi
                ;;
            3) exec_dnf "history" "Shows summary of past DNF actions." "default" "history" ;;
            4)
                tid=$(get_input_text "Transaction Info" "Enter Transaction ID (Integer):")
                if [[ "$tid" =~ ^[0-9]+$ ]]; then
                    exec_dnf "history" "Shows full details of transaction $tid." "default" "history" "info" "$tid"
                elif [ -n "$tid" ]; then
                    show_msg "Invalid ID. Integers only."
                fi
                ;;
            0|*) break ;;
        esac
    done
}

menu_repos() {
    # Check dependency
    if [ "$HAS_PLUGINS" -eq 0 ]; then
        show_msg "Error: 'dnf-plugins-core' is missing.\nCannot manage repositories."
        return
    fi

    while true; do
        $UI_BIN --title "Repository Management" --menu "Select Action:" $H $W $M \
            "1" "List enabled repositories" \
            "2" "Show repository details" \
            "3" "Enable RPM Fusion (Third Party)" \
            "4" "Disable a repository" \
            "5" "Enable a repository" \
            "0" "Back" 2> "$TEMP_FILE"

        case $(cat "$TEMP_FILE") in
            1) exec_dnf "repolist" "Lists active repositories." "default" "repolist" ;;
            2) exec_dnf "repolist" "Shows details of repo configuration." "default" "repolist" "-v" ;;
            3)
                # RPM Fusion Logic
                # URL construction using rpm -E for robustness
                local base="https://mirrors.rpmfusion.org"
                local f_rel=$(rpm -E %fedora)
                local free_rpm="${base}/free/fedora/rpmfusion-free-release-${f_rel}.noarch.rpm"
                local nonfree_rpm="${base}/nonfree/fedora/rpmfusion-nonfree-release-${f_rel}.noarch.rpm"
                
                exec_dnf "install" "Installs RPM Fusion release packages.\nNote: These are third-party repositories not hosted by Fedora." "default" "install" "$free_rpm" "$nonfree_rpm"
                ;;
            4)
                repo=$(get_input_text "Disable Repo" "Enter Repo ID (e.g. updates-testing):")
                if validate_input "$repo" "id"; then
                    exec_dnf "config-manager" "Disables repository '$repo'." "default" "config-manager" "--set-disabled" "$repo"
                fi
                ;;
            5)
                repo=$(get_input_text "Enable Repo" "Enter Repo ID (e.g. updates-testing):")
                if validate_input "$repo" "id"; then
                    exec_dnf "config-manager" "Enables repository '$repo'." "default" "config-manager" "--set-enabled" "$repo"
                fi
                ;;
            0|*) break ;;
        esac
    done
}

menu_advanced() {
    while true; do
        $UI_BIN --title "Advanced / Risky Operations" --menu "Select Operation:" $H $W $M \
            "1" "Distro-Sync (Repair versions)" \
            "2" "Undo Transaction (Rollback)" \
            "3" "Reset Module Stream" \
            "0" "Back" 2> "$TEMP_FILE"

        case $(cat "$TEMP_FILE") in
            1) 
                exec_dnf "distro-sync" "Synchronizes installed packages to latest available versions.\nMay downgrade packages if newer versions are removed from repo." "default" "distro-sync" 
                ;;
            2)
                tid=$(get_input_text "Undo" "Enter Transaction ID to undo:")
                if [[ "$tid" =~ ^[0-9]+$ ]]; then
                    exec_dnf "history" "Attempts to revert actions of transaction $tid.\nWarning: Rollbacks are not guaranteed to be clean." "default" "history" "undo" "$tid"
                fi
                ;;
            3)
                mod=$(get_input_text "Reset Module" "Enter module name:")
                if validate_input "$mod" "module"; then
                    exec_dnf "module" "Resets module stream '$mod' to default." "default" "module" "reset" "$mod"
                fi
                ;;
            0|*) break ;;
        esac
    done
}


# --- Main Logic ---

stage_privileges "$@"
stage_launch

while true; do
    $UI_BIN --title "$APP_TITLE Main Menu" --menu "Select Category:" $H $W 7 \
        "1" "System Health & Maintenance" \
        "2" "Package Management" \
        "3" "Information & History" \
        "4" "Repository Management" \
        "5" "Advanced / Risky Operations" \
        "H" "Help" \
        "0" "Exit" 2> "$TEMP_FILE" || break

    case $(cat "$TEMP_FILE") in
        1) menu_maintenance ;;
        2) menu_packages ;;
        3) menu_info ;;
        4) menu_repos ;;
        5) menu_advanced ;;
        H) menu_help ;;
        0) break ;;
    esac
done

clear
echo "========================================"
echo " sys-wiz session ended"
echo "========================================"
exit 0