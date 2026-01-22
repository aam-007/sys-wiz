#!/usr/bin/bash

# ==============================================================================
# sys-wiz
# Version: 1.1.0 (Fedora Hardened)
# License: MIT / Fedora Project Compatible
#
# A minimalist, safety-first terminal wizard for DNF on Fedora Linux.
# Designed for transparency, reversibility, and maintainability.
#
# Design Principles:
# 1. Zero Magic: No hidden flags, no silent chaining.
# 2. Transparency: User sees the exact command before execution.
# 3. Fedora Native: Strict OS and dependency detection.
# 4. Input Safety: Strict validation of all user input.
# ==============================================================================

# --- Safety Flags ---
set -u
set -o pipefail

# --- Configuration & Constants ---
APP_TITLE="sys-wiz"
APP_VERSION="1.1.0"
TEMP_FILE=$(mktemp)
LOG_FILE=$(mktemp)

# Risk Levels
RISK_INFO="INFO"       # Read-only
RISK_NORMAL="NORMAL"   # Standard install/update
RISK_HIGH="HIGH"       # Removal, Repository changes
RISK_CRITICAL="CRITICAL" # Distro-sync, History Undo, Autoremove

# UI Defaults (Conservative defaults for 80x24 terminals)
H=18
W=74
M=10 # Menu height

# --- Trap Cleanup ---
cleanup() {
    rm -f "$TEMP_FILE" "$LOG_FILE"
    clear
}
trap cleanup EXIT SIGINT SIGTERM

# --- Dependency & Environment Checks ---

# 1. Detect UI Provider
if command -v whiptail >/dev/null; then
    UI_BIN="whiptail"
elif command -v dialog >/dev/null; then
    UI_BIN="dialog"
else
    echo "Error: Missing dependency."
    echo "This tool requires 'newt' (whiptail) or 'dialog'."
    echo "Install: sudo dnf install newt"
    exit 1
fi

# 2. Detect Fedora
if [ -f /etc/os-release ]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    if [ "${ID:-}" != "fedora" ]; then
        echo "Error: Detected OS is '${ID:-unknown}'."
        echo "sys-wiz is designed strictly for Fedora Linux to ensure safety."
        exit 1
    fi
    FEDORA_VERSION="${VERSION_ID:-}"
else
    echo "Error: /etc/os-release missing. Cannot verify OS."
    exit 1
fi

# 3. Detect DNF
if ! command -v dnf >/dev/null; then
    echo "Error: 'dnf' binary not found."
    exit 1
fi
DNF_VERSION=$(dnf --version | head -n 1 | awk '{print $1 " " $2}')

# 4. Detect DNF Plugins (Required for repo management)
HAS_PLUGINS=0
if rpm -q dnf-plugins-core >/dev/null 2>&1; then
    HAS_PLUGINS=1
fi

# --- Helper Functions ---

# Standard message box
show_msg() {
    $UI_BIN --title "$APP_TITLE" --msgbox "$1" 10 60
}

# Input Validator
# Returns 0 if valid, 1 if invalid
# Args: $1=Input String, $2=Type (package|id|path)
validate_input() {
    local input="$1"
    local type="$2"

    if [ -z "$input" ]; then return 1; fi

    case "$type" in
        package|module)
            # Alphanumeric, plus -, _, ., +, : (for epochs)
            if [[ "$input" =~ ^[a-zA-Z0-9\.\_\+\:\-]+$ ]]; then return 0; else return 1; fi
            ;;
        id)
            # Repos usually just alpha-numeric and dashes/underscores
            if [[ "$input" =~ ^[a-zA-Z0-9\.\_\-]+$ ]]; then return 0; else return 1; fi
            ;;
        path)
            # Local file path validation
            if [ -f "$input" ]; then return 0; else return 1; fi
            ;;
        *)
            return 1
            ;;
    esac
}

# Execute DNF Command (The Core Logic)
# Args:
#   $1: Description (Plain English)
#   $2: Risk Level (INFO|NORMAL|HIGH|CRITICAL)
#   $3...: The DNF subcommand and arguments as separate parameters
exec_dnf() {
    local description="$1"
    local risk="$2"
    shift 2
    local dnf_args=("$@")
    
    # Construct display string safely
    local cmd_display="dnf ${dnf_args[*]}"

    local title="Confirm Action"
    local prompt_text=""
    
    # Risk-based UI Context
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
        
        # Execution Phase
        clear
        echo "----------------------------------------------------------------"
        echo " timestamp : $(date '+%Y-%m-%d %H:%M:%S')"
        echo " command   : dnf ${dnf_args[*]}"
        echo " intent    : $description"
        echo "----------------------------------------------------------------"
        
        # Run Sudo DNF
        # effectively using quotes to handle arguments correctly
        sudo dnf "${dnf_args[@]}"
        local ret=$?
        
        echo "----------------------------------------------------------------"
        if [ $ret -eq 0 ]; then
            echo "Status: COMPLETED SUCCESSFULLY"
        else
            echo "Status: FAILED (Exit Code: $ret)"
        fi
        echo "----------------------------------------------------------------"
        echo "Press Enter to return..."
        read -r
    else
        show_msg "Action cancelled."
    fi
}

# Get Input Helper
get_input_text() {
    local title="$1"
    local text="$2"
    $UI_BIN --title "$title" --inputbox "$text" 10 60 2> "$TEMP_FILE"
    if [ $? -eq 0 ]; then
        cat "$TEMP_FILE"
    else
        echo ""
    fi
}

# --- Functional Stages ---

stage_launch() {
    clear
    # Simple, boring header
    echo "sys-wiz v$APP_VERSION"
    echo "Fedora $FEDORA_VERSION | $DNF_VERSION"
    echo "----------------------------------------"
    echo "Guided, transparent DNF package manager."
    echo ""
    
    if [ "$HAS_PLUGINS" -eq 0 ]; then
        echo "WARNING: 'dnf-plugins-core' is missing."
        echo "         Repository management features will be disabled."
        echo ""
    fi

    echo "Press Enter to start..."
    read -r
}

stage_privileges() {
    if [ "$(id -u)" -ne 0 ]; then
        clear
        echo "Authorization Required"
        echo "----------------------"
        echo "This tool modifies system state."
        echo "Please enter your sudo password."
        echo ""
        if ! sudo -v; then
            echo ""
            echo "Authentication failed. Aborting."
            exit 1
        fi
    fi
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
            1) exec_dnf "Checks for available updates without installing them." "$RISK_INFO" "check-update" ;;
            2) exec_dnf "Upgrades all installed packages to the latest version." "$RISK_NORMAL" "upgrade" ;;
            3) exec_dnf "Refreshes repository metadata, then upgrades system." "$RISK_NORMAL" "upgrade" "--refresh" ;;
            4) exec_dnf "Checks local RPM database for broken dependencies." "$RISK_INFO" "check" ;;
            5) exec_dnf "Removes packages no longer needed by any installed software." "$RISK_CRITICAL" "autoremove" ;;
            6) exec_dnf "Removes all cached package data. Frees disk space but slows next update." "$RISK_HIGH" "clean" "all" ;;
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
                    exec_dnf "Searches repository metadata." "$RISK_INFO" "search" "$term"
                else
                    [ -n "$term" ] && show_msg "Invalid input. Alphanumeric only."
                fi
                ;;
            2)
                file=$(get_input_text "Identify Provider" "Enter file name or path (e.g., /usr/bin/ls):")
                if [ -n "$file" ]; then # relaxed validation for paths/files
                    exec_dnf "Finds which package owns the specified file." "$RISK_INFO" "provides" "$file"
                fi
                ;;
            3)
                pkg=$(get_input_text "Install" "Enter package name:")
                if validate_input "$pkg" "package"; then
                    exec_dnf "Installs '$pkg' and dependencies." "$RISK_NORMAL" "install" "$pkg"
                elif [ -n "$pkg" ]; then
                    show_msg "Invalid package name."
                fi
                ;;
            4)
                path=$(get_input_text "Local Install" "Enter absolute path to .rpm file:")
                if validate_input "$path" "path"; then
                    exec_dnf "Installs local RPM file using DNF (resolves deps)." "$RISK_NORMAL" "install" "$path"
                elif [ -n "$path" ]; then
                    show_msg "File not found or invalid path."
                fi
                ;;
            5)
                pkg=$(get_input_text "Remove" "Enter package name:")
                if validate_input "$pkg" "package"; then
                    exec_dnf "Removes '$pkg'. Review list of dependents carefully!" "$RISK_HIGH" "remove" "$pkg"
                fi
                ;;
            6)
                pkg=$(get_input_text "Reinstall" "Enter package name:")
                if validate_input "$pkg" "package"; then
                    exec_dnf "Reinstalls current version of '$pkg'." "$RISK_NORMAL" "reinstall" "$pkg"
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
            1) exec_dnf "Lists all installed packages." "$RISK_INFO" "list" "installed" ;;
            2) 
                pkg=$(get_input_text "Package Info" "Enter package name:")
                if validate_input "$pkg" "package"; then
                    exec_dnf "Displays metadata for '$pkg'." "$RISK_INFO" "info" "$pkg"
                fi
                ;;
            3) exec_dnf "Shows summary of past DNF actions." "$RISK_INFO" "history" ;;
            4)
                tid=$(get_input_text "Transaction Info" "Enter Transaction ID (Integer):")
                if [[ "$tid" =~ ^[0-9]+$ ]]; then
                    exec_dnf "Shows full details of transaction $tid." "$RISK_INFO" "history" "info" "$tid"
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
            1) exec_dnf "Lists active repositories." "$RISK_INFO" "repolist" ;;
            2) exec_dnf "Shows details of repo configuration." "$RISK_INFO" "repolist" "-v" ;;
            3)
                # RPM Fusion Logic
                # URL construction using rpm -E for robustness
                local base="https://mirrors.rpmfusion.org"
                local f_rel=$(rpm -E %fedora)
                local free_rpm="${base}/free/fedora/rpmfusion-free-release-${f_rel}.noarch.rpm"
                local nonfree_rpm="${base}/nonfree/fedora/rpmfusion-nonfree-release-${f_rel}.noarch.rpm"
                
                exec_dnf "Installs RPM Fusion release packages.\nNote: These are third-party repositories not hosted by Fedora." \
                    "$RISK_HIGH" "install" "$free_rpm" "$nonfree_rpm"
                ;;
            4)
                repo=$(get_input_text "Disable Repo" "Enter Repo ID (e.g. updates-testing):")
                if validate_input "$repo" "id"; then
                    exec_dnf "Disables repository '$repo'." "$RISK_HIGH" "config-manager" "--set-disabled" "$repo"
                fi
                ;;
            5)
                repo=$(get_input_text "Enable Repo" "Enter Repo ID (e.g. updates-testing):")
                if validate_input "$repo" "id"; then
                    exec_dnf "Enables repository '$repo'." "$RISK_HIGH" "config-manager" "--set-enabled" "$repo"
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
                exec_dnf "Synchronizes installed packages to latest available versions.\nMay downgrade packages if newer versions are removed from repo." \
                "$RISK_CRITICAL" "distro-sync" 
                ;;
            2)
                tid=$(get_input_text "Undo" "Enter Transaction ID to undo:")
                if [[ "$tid" =~ ^[0-9]+$ ]]; then
                    exec_dnf "Attempts to revert actions of transaction $tid.\nWarning: Rollbacks are not guaranteed to be clean." \
                    "$RISK_CRITICAL" "history" "undo" "$tid"
                fi
                ;;
            3)
                mod=$(get_input_text "Reset Module" "Enter module name:")
                if validate_input "$mod" "module"; then
                    exec_dnf "Resets module stream '$mod' to default." "$RISK_HIGH" "module" "reset" "$mod"
                fi
                ;;
            0|*) break ;;
        esac
    done
}

# --- Main Logic ---

stage_launch
stage_privileges

# Main Loop
while true; do
    $UI_BIN --title "$APP_TITLE Main Menu" --menu "Select Category:" $H $W 7 \
        "1" "System Health & Maintenance" \
        "2" "Package Management" \
        "3" "Information & History" \
        "4" "Repository Management" \
        "5" "Advanced / Risky Operations" \
        "H" "Help" \
        "0" "Exit" 2> "$TEMP_FILE"

    if [ $? -ne 0 ]; then
        break
    fi

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

# Exit Summary
clear
echo "========================================"
echo " sys-wiz session ended"
echo "========================================"
echo " No background processes were left running."
echo " Temporary files have been cleaned up."
echo " Stay safe."
echo "========================================"
exit 0