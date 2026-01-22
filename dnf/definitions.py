from dataclasses import dataclass
from typing import Optional

@dataclass
class CommandDef:
    title: str
    description: str
    command_template: str 
    is_risky: bool = False
    needs_input: bool = False
    input_prompt: Optional[str] = None

# Organized by Category
COMMANDS = {
    "System Health": {
        "update": CommandDef(
            "Update System",
            "Downloads and installs updates for all packages. Safe standard procedure.",
            "sudo dnf upgrade --refresh"
        ),
        "cleanup": CommandDef(
            "Update & Cleanup",
            "Updates system and then removes cached metadata to free space.",
            "sudo dnf upgrade --refresh && sudo dnf clean packages"
        ),
        "broken": CommandDef(
            "Check Broken Dependencies",
            "Scans for packages with missing requirements.",
            "sudo dnf repoquery --unsatisfied"
        ),
        "orphans": CommandDef(
            "List Orphaned Packages",
            "Lists packages installed as dependencies that are no longer needed.",
            "sudo dnf autoremove --assumeno"
        )
    },
    "Install / Remove": {
        "search": CommandDef(
            "Search Packages",
            "Search repositories for a package by keyword.",
            "dnf search {}",
            needs_input=True,
            input_prompt="Enter keyword to search:"
        ),
        "install": CommandDef(
            "Install Package",
            "Installs a specific package.",
            "sudo dnf install {}",
            needs_input=True,
            input_prompt="Enter package name:"
        ),
        "remove": CommandDef(
            "Remove Package",
            "Removes a package. WARNING: Check dependencies before confirming.",
            "sudo dnf remove {}",
            is_risky=True,
            needs_input=True,
            input_prompt="Enter package name to remove:"
        ),
        "reinstall": CommandDef(
            "Reinstall Package",
            "Re-downloads and installs the current version of a package.",
            "sudo dnf reinstall {}",
            needs_input=True,
            input_prompt="Enter package name:"
        )
    },
    "Discovery": {
        "list_installed": CommandDef(
            "Show Installed Packages",
            "Lists all currently installed RPMs.",
            "dnf list installed"
        ),
        "info": CommandDef(
            "Package Information",
            "Show details about a specific package.",
            "dnf info {}",
            needs_input=True,
            input_prompt="Enter package name:"
        )
    },
    "Repositories": {
        "list_repos": CommandDef(
            "List Enabled Repos",
            "Shows which software sources are currently active.",
            "dnf repolist"
        ),
        "enable_fusion": CommandDef(
            "Enable RPM Fusion (Free/Nonfree)",
            "Enables the standard third-party repos for codecs and drivers.",
            "sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
        )
    },
    "Power / Risky": {
        "distro_sync": CommandDef(
            "Distro Sync",
            "Synchronizes installed packages to the latest available versions. Can downgrade packages.",
            "sudo dnf distro-sync",
            is_risky=True
        ),
        "history_rollback": CommandDef(
            "Rollback (Last Transaction)",
            "Undoes the very last DNF action. Use with extreme caution.",
            "sudo dnf history undo last",
            is_risky=True
        ),
        "clean_all": CommandDef(
            "Clean All Caches",
            "Removes all cached metadata and packages. Forces full redownload next time.",
            "sudo dnf clean all",
            is_risky=True
        )
    }
}