set -e
readonly SCRIPT_VERSION="1.0"
readonly REQUIREMENTS="dnf sudo whiptail"

# Detect terminal capabilities
if [ -z "$TERM" ] || [ "$TERM" = "dumb" ]; then
    echo "Error: Terminal not supported. Please use a proper terminal emulator." >&2
    exit 1
fi

# Check if we're on Fedora
if [ ! -f /etc/fedora-release ]; then
    echo "Error: This tool is designed for Fedora Linux only." >&2
    exit 1
fi

# Source Fedora version info
. /etc/os-release 2>/dev/null || VERSION_ID="unknown"
FEDORA_VERSION="${VERSION_ID:-unknown}"
DNF_VERSION=$(dnf --version 2>/dev/null | head -n1 | cut -d' ' -f3 || echo "unknown")

# UI backend selection (prefer whiptail)
if command -v whiptail >/dev/null 2>&1; then
    DIALOG=whiptail
elif command -v dialog >/dev/null 2>&1; then
    DIALOG=dialog
else
    echo "Error: Please install either 'whiptail' or 'dialog' package." >&2
    exit 1
fi

# Check for required tools
for cmd in $REQUIREMENTS; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: Required command '$cmd' not found." >&2
        exit 1
    fi
done

# Sudo credential caching
check_sudo() {
    if ! sudo -v; then
        $DIALOG --msgbox "sudo authentication failed. Exiting." 8 60
        exit 1
    fi
}

# Safe command execution with explanation
execute_dnf() {
    local cmd="$1"
    local explanation="$2"
    local next_suggestion="$3"
    
    # Show command and explanation
    $DIALOG --yesno "Command to execute:\n\n$cmd\n\n$explanation\n\nProceed?" 16 80
    if [ $? -eq 0 ]; then
        # Execute and capture output
        local output_file
        output_file=$(mktemp)
        if eval "sudo $cmd" >"$output_file" 2>&1; then
            $DIALOG --scrolltext --title "Success" --msgbox "Command completed successfully.\n\nOutput:\n$(cat "$output_file")" 20 80
        else
            $DIALOG --scrolltext --title "Error" --msgbox "Command failed.\n\nOutput:\n$(cat "$output_file")" 20 80
        fi
        rm -f "$output_file"
        
        # Suggest next step if provided
        if [ -n "$next_suggestion" ]; then
            $DIALOG --msgbox "$next_suggestion" 10 60
        fi
    else
        $DIALOG --msgbox "Operation cancelled." 8 50
    fi
}

# Package selection dialog
select_package() {
    local title="$1"
    local action="$2"
    local packages
    local package_list=""
    
    case "$action" in
        install)
            $DIALOG --inputbox "Enter package name to search:" 10 60 2>/tmp/sys-wiz-search
            [ $? -ne 0 ] && return 1
            local search_term
            search_term=$(cat /tmp/sys-wiz-search)
            rm -f /tmp/sys-wiz-search
            
            packages=$(dnf search "$search_term" 2>/dev/null | grep -E "^[a-zA-Z0-9_\-\.]+" | head -30 | while read -r pkg desc; do
                echo "\"$pkg\" \"$desc\""
            done)
            eval $DIALOG --menu "Select package to install:" 20 80 13 $packages 2>/tmp/sys-wiz-pkg
            ;;
        
        remove)
            packages=$(dnf list installed 2>/dev/null | tail -n+2 | awk '{print $1}' | sort | while read -r pkg; do
                echo "\"$pkg\" \"\""
            done)
            eval $DIALOG --menu "Select package to remove:" 20 80 13 $packages 2>/tmp/sys-wiz-pkg
            ;;
    esac
    
    if [ $? -eq 0 ] && [ -s /tmp/sys-wiz-pkg ]; then
        local selected
        selected=$(cat /tmp/sys-wiz-pkg)
        rm -f /tmp/sys-wiz-pkg
        echo "$selected"
    else
        rm -f /tmp/sys-wiz-pkg
        echo ""
    fi
}

# Main menu functions
system_maintenance() {
    while true; do
        local choice
        choice=$($DIALOG --menu "System Maintenance" 15 60 7 \
            1 "Update system" \
            2 "Update system (with suggested cleanup)" \
            3 "List orphaned packages" \
            4 "Remove orphaned packages" \
            5 "Check dependency issues" \
            6 "Back" \
            2>&1)
        
        case $choice in
            1)
                execute_dnf "dnf upgrade" \
                    "Update all installed packages to their latest available versions." \
                    "Consider checking for orphaned packages next."
                ;;
            2)
                execute_dnf "dnf upgrade --refresh" \
                    "Update package metadata and upgrade all packages, removing unnecessary dependencies." \
                    "You may want to check dependency issues next."
                ;;
            3)
                execute_dnf "dnf list extras" \
                    "List packages that are no longer required by any installed package." \
                    "You can remove orphaned packages if the list looks reasonable."
                ;;
            4)
                $DIALOG --yesno "Warning: This will remove packages not required by any installed package.\n\nReview the list first to avoid removing wanted packages.\n\nProceed to confirmation?" 12 70
                if [ $? -eq 0 ]; then
                    execute_dnf "dnf autoremove" \
                        "Remove packages that are no longer required." \
                        "Check dependency issues to verify system health."
                fi
                ;;
            5)
                execute_dnf "dnf repoquery --unsatisfied" \
                    "Check for dependency problems in the package database." \
                    "If problems are found, consider reinstalling affected packages."
                ;;
            6)
                break
                ;;
        esac
    done
}

install_remove() {
    while true; do
        local choice
        choice=$($DIALOG --menu "Install & Remove" 15 60 7 \
            1 "Search and install package" \
            2 "Remove package" \
            3 "Reinstall package" \
            4 "Downgrade package" \
            5 "Back" \
            2>&1)
        
        case $choice in
            1)
                local pkg
                pkg=$(select_package "Install Package" "install")
                if [ -n "$pkg" ]; then
                    execute_dnf "dnf install $pkg" \
                        "Install package $pkg and its dependencies." \
                        "Package installed. Check 'List installed packages' to verify."
                fi
                ;;
            2)
                local pkg
                pkg=$(select_package "Remove Package" "remove")
                if [ -n "$pkg" ]; then
                    $DIALOG --yesno "Warning: Removing package $pkg\n\nThis will also remove dependencies that are no longer needed.\n\nProceed?" 12 70
                    if [ $? -eq 0 ]; then
                        execute_dnf "dnf remove $pkg" \
                            "Remove package $pkg and unused dependencies." \
                            "Package removed. Consider checking for orphaned packages."
                    fi
                fi
                ;;
            3)
                local pkg
                pkg=$(select_package "Reinstall Package" "remove")
                if [ -n "$pkg" ]; then
                    execute_dnf "dnf reinstall $pkg" \
                        "Reinstall package $pkg with current repository versions." \
                        "Package reinstalled."
                fi
                ;;
            4)
                $DIALOG --inputbox "Enter package name to downgrade:" 10 60 2>/tmp/sys-wiz-downgrade
                if [ $? -eq 0 ]; then
                    local pkg
                    pkg=$(cat /tmp/sys-wiz-downgrade)
                    rm -f /tmp/sys-wiz-downgrade
                    
                    if [ -n "$pkg" ]; then
                        execute_dnf "dnf downgrade $pkg" \
                            "Downgrade $pkg to an older version from repositories." \
                            "Package downgraded. Check version with 'Show package details'."
                    fi
                else
                    rm -f /tmp/sys-wiz-downgrade
                fi
                ;;
            5)
                break
                ;;
        esac
    done
}

information() {
    while true; do
        local choice
        choice=$($DIALOG --menu "Information" 15 60 7 \
            1 "List installed packages" \
            2 "Show package details" \
            3 "Show DNF history" \
            4 "Back" \
            2>&1)
        
        case $choice in
            1)
                execute_dnf "dnf list installed" \
                    "List all installed packages with versions." \
                    "Use 'Show package details' for more information on specific packages."
                ;;
            2)
                $DIALOG --inputbox "Enter package name for details:" 10 60 2>/tmp/sys-wiz-info
                if [ $? -eq 0 ]; then
                    local pkg
                    pkg=$(cat /tmp/sys-wiz-info)
                    rm -f /tmp/sys-wiz-info
                    
                    if [ -n "$pkg" ]; then
                        execute_dnf "dnf info $pkg" \
                            "Show detailed information about package $pkg." \
                            ""
                    fi
                else
                    rm -f /tmp/sys-wiz-info
                fi
                ;;
            3)
                execute_dnf "dnf history" \
                    "Show DNF transaction history." \
                    "Use 'Roll back a DNF transaction' in Advanced menu if needed."
                ;;
            4)
                break
                ;;
        esac
    done
}

repositories() {
    while true; do
        local choice
        choice=$($DIALOG --menu "Repositories" 15 60 7 \
            1 "List enabled repositories" \
            2 "Enable RPM Fusion (free)" \
            3 "Enable RPM Fusion (nonfree)" \
            4 "Disable repository" \
            5 "Back" \
            2>&1)
        
        case $choice in
            1)
                execute_dnf "dnf repolist enabled" \
                    "List all enabled DNF repositories." \
                    ""
                ;;
            2)
                $DIALOG --yesno "RPM Fusion provides software not included in Fedora.\n\nThis will enable the free repository.\n\nProceed?" 12 70
                if [ $? -eq 0 ]; then
                    execute_dnf "dnf install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-\$(rpm -E %fedora).noarch.rpm" \
                        "Enable RPM Fusion free repository for additional open-source software." \
                        "Repository enabled. You may need to run 'dnf upgrade --refresh'."
                fi
                ;;
            3)
                $DIALOG --yesno "RPM Fusion provides software not included in Fedora.\n\nThis will enable the nonfree repository (patents/legal restrictions).\n\nProceed?" 12 70
                if [ $? -eq 0 ]; then
                    execute_dnf "dnf install https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-\$(rpm -E %fedora).noarch.rpm" \
                        "Enable RPM Fusion nonfree repository for software with usage restrictions." \
                        "Repository enabled. You may need to run 'dnf upgrade --refresh'."
                fi
                ;;
            4)
                $DIALOG --inputbox "Enter repository ID to disable:" 10 60 2>/tmp/sys-wiz-repo
                if [ $? -eq 0 ]; then
                    local repo
                    repo=$(cat /tmp/sys-wiz-repo)
                    rm -f /tmp/sys-wiz-repo
                    
                    if [ -n "$repo" ]; then
                        execute_dnf "dnf config-manager --set-disabled $repo" \
                            "Disable repository $repo." \
                            "Repository disabled. Use 'List enabled repositories' to verify."
                    fi
                else
                    rm -f /tmp/sys-wiz-repo
                fi
                ;;
            5)
                break
                ;;
        esac
    done
}

advanced() {
    while true; do
        local choice
        choice=$($DIALOG --menu "Advanced / Risky Operations" 17 70 8 \
            1 "dnf distro-sync (warning: may change many packages)" \
            2 "Roll back a DNF transaction" \
            3 "Reset DNF modules" \
            4 "Clean all DNF caches" \
            5 "Back" \
            2>&1)
        
        case $choice in
            1)
                $DIALOG --yesno "WARNING: distro-sync may downgrade or upgrade many packages to match the repository.\n\nThis can have significant system impact.\n\nProceed to confirmation?" 14 70
                if [ $? -eq 0 ]; then
                    execute_dnf "dnf distro-sync" \
                        "Synchronize installed packages to the current repository versions (may downgrade)." \
                        "Distro-sync completed. Review changes carefully."
                fi
                ;;
            2)
                $DIALOG --inputbox "Enter transaction ID to rollback (from DNF history):" 10 60 2>/tmp/sys-wiz-trans
                if [ $? -eq 0 ]; then
                    local trans
                    trans=$(cat /tmp/sys-wiz-trans)
                    rm -f /tmp/sys-wiz-trans
                    
                    if [ -n "$trans" ]; then
                        execute_dnf "dnf history rollback $trans" \
                            "Roll back system to state before transaction $trans." \
                            "Rollback completed. Check 'dnf history' to verify."
                    fi
                else
                    rm -f /tmp/sys-wiz-trans
                fi
                ;;
            3)
                $DIALOG --yesno "WARNING: This will reset all module streams to their default states.\n\nProceed?" 12 70
                if [ $? -eq 0 ]; then
                    execute_dnf "dnf module reset -y" \
                        "Reset all module streams to default states." \
                        "Modules reset. Use 'dnf module list' to see current state."
                fi
                ;;
            4)
                execute_dnf "dnf clean all" \
                    "Remove all cached package data and metadata." \
                    "Caches cleaned. Next DNF operation will download fresh metadata."
                ;;
            5)
                break
                ;;
        esac
    done
}

# Initialization
clear
cat <<EOF
sys-wiz
Version: $SCRIPT_VERSION
Fedora version: $FEDORA_VERSION
DNF version: $DNF_VERSION

A guided terminal interface for safe DNF package management.

Press Enter to continue
EOF
read -r _

# Privilege escalation
$DIALOG --msgbox "This tool manages system packages and requires administrator privileges." 8 60
check_sudo

# Main menu loop
while true; do
    local main_choice
    main_choice=$($DIALOG --menu "Main Menu" 17 60 10 \
        1 "System Maintenance" \
        2 "Install & Remove" \
        3 "Information" \
        4 "Repositories" \
        5 "Advanced / Risky" \
        6 "Exit" \
        2>&1)
    
    case $main_choice in
        1) system_maintenance ;;
        2) install_remove ;;
        3) information ;;
        4) repositories ;;
        5) advanced ;;
        6) break ;;
    esac
done

$DIALOG --msgbox "Thank you for using sys-wiz." 8 40
clear