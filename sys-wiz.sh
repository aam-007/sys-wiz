#!/bin/sh
set -e
SCRIPT_VERSION="1.0"
REQUIREMENTS="dnf sudo"

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

# Check for UI tool
if command -v whiptail >/dev/null 2>&1; then
    DIALOG=whiptail
elif command -v dialog >/dev/null 2>&1; then
    DIALOG=dialog
else
    # Fall back to simple text menu
    DIALOG=none
fi

# Check for required tools
for cmd in $REQUIREMENTS; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: Required command '$cmd' not found." >&2
        exit 1
    fi
done

# Simple text-based menu for fallback
simple_menu() {
    echo ""
    echo "$1"
    echo "========================================"
    shift
    i=1
    for item in "$@"; do
        echo "  $i. $item"
        i=$((i + 1))
    done
    echo ""
    printf "Enter choice (1-%d): " $(($#))
    read -r choice
    echo "$choice"
}

# Sudo credential caching
check_sudo() {
    echo "This tool manages system packages and requires administrator privileges."
    echo "Please enter your password when prompted."
    echo ""
    if ! sudo -v; then
        echo "sudo authentication failed. Exiting." >&2
        exit 1
    fi
}

# Safe command execution with explanation
execute_dnf() {
    cmd="$1"
    explanation="$2"
    
    echo ""
    echo "Command to execute:"
    echo "  $cmd"
    echo ""
    echo "Explanation:"
    echo "  $explanation"
    echo ""
    
    while true; do
        printf "Proceed? (y/n): "
        read -r confirm
        case "$confirm" in
            [Yy]*)
                echo ""
                echo "Running command..."
                echo "========================================"
                if sudo $cmd; then
                    echo "========================================"
                    echo "Command completed successfully."
                else
                    echo "========================================"
                    echo "Command failed with exit code $?."
                fi
                break
                ;;
            [Nn]*)
                echo "Operation cancelled."
                break
                ;;
            *)
                echo "Please answer y or n."
                ;;
        esac
    done
    
    echo ""
    printf "Press Enter to continue..."
    read -r
}

# Package selection
select_package() {
    action="$1"
    
    printf "Enter package name: "
    read -r pkgname
    
    if [ -z "$pkgname" ]; then
        echo "No package name entered."
        return 1
    fi
    
    case "$action" in
        install)
            echo "Searching for package: $pkgname"
            dnf search "$pkgname" | head -20
            echo ""
            printf "Install package '$pkgname'? (y/n): "
            read -r confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                execute_dnf "dnf install $pkgname" \
                    "Install package $pkgname and its dependencies."
            fi
            ;;
        remove)
            echo "Checking if package is installed: $pkgname"
            if dnf list installed "$pkgname" >/dev/null 2>&1; then
                printf "WARNING: Remove package '$pkgname'? This will also remove unused dependencies. (y/n): "
                read -r confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    execute_dnf "dnf remove $pkgname" \
                        "Remove package $pkgname and unused dependencies."
                fi
            else
                echo "Package '$pkgname' is not installed."
            fi
            ;;
        info)
            execute_dnf "dnf info $pkgname" \
                "Show detailed information about package $pkgname."
            ;;
        reinstall)
            if dnf list installed "$pkgname" >/dev/null 2>&1; then
                execute_dnf "dnf reinstall $pkgname" \
                    "Reinstall package $pkgname with current repository versions."
            else
                echo "Package '$pkgname' is not installed."
            fi
            ;;
    esac
}

# System maintenance menu
system_maintenance() {
    while true; do
        if [ "$DIALOG" = "none" ]; then
            choice=$(simple_menu "System Maintenance" \
                "Update system" \
                "Update system (with suggested cleanup)" \
                "List orphaned packages" \
                "Remove orphaned packages" \
                "Check dependency issues" \
                "Back")
        else
            choice=$($DIALOG --menu "System Maintenance" 15 60 7 \
                1 "Update system" \
                2 "Update system (with suggested cleanup)" \
                3 "List orphaned packages" \
                4 "Remove orphaned packages" \
                5 "Check dependency issues" \
                6 "Back" \
                3>&1 1>&2 2>&3)
        fi
        
        case $choice in
            1)
                execute_dnf "dnf upgrade" \
                    "Update all installed packages to their latest available versions."
                ;;
            2)
                execute_dnf "dnf upgrade --refresh" \
                    "Update package metadata and upgrade all packages, removing unnecessary dependencies."
                ;;
            3)
                execute_dnf "dnf list extras" \
                    "List packages that are no longer required by any installed package."
                ;;
            4)
                echo "WARNING: This will remove packages not required by any installed package."
                echo "Review the list first to avoid removing wanted packages."
                echo ""
                dnf list extras
                echo ""
                printf "Proceed with removing orphaned packages? (y/n): "
                read -r confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    execute_dnf "dnf autoremove" \
                        "Remove packages that are no longer required."
                fi
                ;;
            5)
                execute_dnf "dnf repoquery --unsatisfied" \
                    "Check for dependency problems in the package database."
                ;;
            6)
                break
                ;;
        esac
    done
}

# Install & Remove menu
install_remove() {
    while true; do
        if [ "$DIALOG" = "none" ]; then
            choice=$(simple_menu "Install & Remove" \
                "Search and install package" \
                "Remove package" \
                "Reinstall package" \
                "Show package details" \
                "Back")
        else
            choice=$($DIALOG --menu "Install & Remove" 15 60 7 \
                1 "Search and install package" \
                2 "Remove package" \
                3 "Reinstall package" \
                4 "Show package details" \
                5 "Back" \
                3>&1 1>&2 2>&3)
        fi
        
        case $choice in
            1) select_package install ;;
            2) select_package remove ;;
            3) select_package reinstall ;;
            4) select_package info ;;
            5) break ;;
        esac
    done
}

# Information menu
information() {
    while true; do
        if [ "$DIALOG" = "none" ]; then
            choice=$(simple_menu "Information" \
                "List installed packages" \
                "Show DNF history" \
                "List enabled repositories" \
                "Back")
        else
            choice=$($DIALOG --menu "Information" 15 60 7 \
                1 "List installed packages" \
                2 "Show DNF history" \
                3 "List enabled repositories" \
                4 "Back" \
                3>&1 1>&2 2>&3)
        fi
        
        case $choice in
            1)
                execute_dnf "dnf list installed" \
                    "List all installed packages with versions."
                ;;
            2)
                execute_dnf "dnf history" \
                    "Show DNF transaction history."
                ;;
            3)
                execute_dnf "dnf repolist enabled" \
                    "List all enabled DNF repositories."
                ;;
            4)
                break
                ;;
        esac
    done
}

# Repositories menu
repositories() {
    while true; do
        if [ "$DIALOG" = "none" ]; then
            choice=$(simple_menu "Repositories" \
                "List enabled repositories" \
                "Enable RPM Fusion (free)" \
                "Enable RPM Fusion (nonfree)" \
                "Disable repository" \
                "Back")
        else
            choice=$($DIALOG --menu "Repositories" 15 60 7 \
                1 "List enabled repositories" \
                2 "Enable RPM Fusion (free)" \
                3 "Enable RPM Fusion (nonfree)" \
                4 "Disable repository" \
                5 "Back" \
                3>&1 1>&2 2>&3)
        fi
        
        case $choice in
            1)
                execute_dnf "dnf repolist enabled" \
                    "List all enabled DNF repositories."
                ;;
            2)
                echo "RPM Fusion provides software not included in Fedora."
                echo "This will enable the free repository."
                echo ""
                printf "Proceed? (y/n): "
                read -r confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    fedora_version=$(rpm -E %fedora 2>/dev/null || echo "unknown")
                    execute_dnf "dnf install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-\$fedora_version.noarch.rpm" \
                        "Enable RPM Fusion free repository for additional open-source software."
                fi
                ;;
            3)
                echo "RPM Fusion provides software not included in Fedora."
                echo "This will enable the nonfree repository (patents/legal restrictions)."
                echo ""
                printf "Proceed? (y/n): "
                read -r confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    fedora_version=$(rpm -E %fedora 2>/dev/null || echo "unknown")
                    execute_dnf "dnf install https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-\$fedora_version.noarch.rpm" \
                        "Enable RPM Fusion nonfree repository for software with usage restrictions."
                fi
                ;;
            4)
                printf "Enter repository ID to disable: "
                read -r repo
                if [ -n "$repo" ]; then
                    execute_dnf "dnf config-manager --set-disabled $repo" \
                        "Disable repository $repo."
                fi
                ;;
            5)
                break
                ;;
        esac
    done
}

# Advanced menu
advanced() {
    while true; do
        if [ "$DIALOG" = "none" ]; then
            choice=$(simple_menu "Advanced / Risky Operations" \
                "dnf distro-sync (warning: may change many packages)" \
                "Clean all DNF caches" \
                "Back")
        else
            choice=$($DIALOG --menu "Advanced / Risky Operations" 15 60 7 \
                1 "dnf distro-sync (warning: may change many packages)" \
                2 "Clean all DNF caches" \
                3 "Back" \
                3>&1 1>&2 2>&3)
        fi
        
        case $choice in
            1)
                echo "WARNING: distro-sync may downgrade or upgrade many packages to match the repository."
                echo "This can have significant system impact."
                echo ""
                printf "Proceed? (y/n): "
                read -r confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    execute_dnf "dnf distro-sync" \
                        "Synchronize installed packages to the current repository versions (may downgrade)."
                fi
                ;;
            2)
                execute_dnf "dnf clean all" \
                    "Remove all cached package data and metadata."
                ;;
            3)
                break
                ;;
        esac
    done
}

# Main initialization
main() {
    clear
    cat <<EOF
sys-wiz
Version: $SCRIPT_VERSION
Fedora version: $(cat /etc/fedora-release 2>/dev/null || echo "unknown")
DNF version: $(dnf --version 2>/dev/null | head -n1 | cut -d' ' -f3 || echo "unknown")

A guided terminal interface for safe DNF package management.

Press Enter to continue
EOF
    read -r _
    
    check_sudo
    
    # Main menu loop
    while true; do
        if [ "$DIALOG" = "none" ]; then
            choice=$(simple_menu "Main Menu" \
                "System Maintenance" \
                "Install & Remove" \
                "Information" \
                "Repositories" \
                "Advanced / Risky" \
                "Exit")
        else
            choice=$($DIALOG --menu "Main Menu" 17 60 10 \
                1 "System Maintenance" \
                2 "Install & Remove" \
                3 "Information" \
                4 "Repositories" \
                5 "Advanced / Risky" \
                6 "Exit" \
                3>&1 1>&2 2>&3)
        fi
        
        case $choice in
            1) system_maintenance ;;
            2) install_remove ;;
            3) information ;;
            4) repositories ;;
            5) advanced ;;
            6) break ;;
        esac
    done
    
    echo "Thank you for using sys-wiz."
    echo ""
}

# Run main function
main