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

COMMANDS = {
    "System Health": {
        "update": CommandDef(
            "Update System",
            "Downloads and installs updates. Safe standard procedure.",
            "sudo dnf upgrade --refresh"
        ),
        "cleanup": CommandDef(
            "Update & Cleanup",
            "Updates system and removes cached metadata.",
            "sudo dnf upgrade --refresh && sudo dnf clean packages"
        ),
        "broken": CommandDef(
            "Check Broken Dependencies",
            "Scans for packages with missing requirements.",
            "sudo dnf repoquery --unsatisfied"
        ),
        "orphans": CommandDef(
            "List Orphaned Packages",
            "Lists unneeded dependencies.",
            "sudo dnf autoremove --assumeno"
        )
    },
    "Install / Remove": {
        "search": CommandDef(
            "Search Packages",
            "Search repositories by keyword.",
            "dnf search {}",
            needs_input=True,
            input_prompt="Enter keyword:"
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
            "Removes a package. WARNING: Check dependencies.",
            "sudo dnf remove {}",
            is_risky=True,
            needs_input=True,
            input_prompt="Enter package name to remove:"
        ),
         "reinstall": CommandDef(
            "Reinstall Package",
            "Re-downloads and installs the current version.",
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
            "Shows active software sources.",
            "dnf repolist"
        ),
        "enable_fusion": CommandDef(
            "Enable RPM Fusion",
            "Enables third-party repos for codecs/drivers.",
            "sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
        )
    },
    "Power / Risky": {
        "distro_sync": CommandDef(
            "Distro Sync",
            "Synchronizes packages to latest versions. Can downgrade.",
            "sudo dnf distro-sync",
            is_risky=True
        ),
        "history_rollback": CommandDef(
            "Rollback (Last Transaction)",
            "Undoes the last DNF action.",
            "sudo dnf history undo last",
            is_risky=True
        ),
        "clean_all": CommandDef(
            "Clean All Caches",
            "Removes all cached metadata and packages.",
            "sudo dnf clean all",
            is_risky=True
        )
    }
}
