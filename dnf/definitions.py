from typing import Dict, List, NamedTuple

class DnfCommand(NamedTuple):
    title: str
    description: str
    cmd: List[str]
    risky: bool = False
    input_required: bool = False # If True, prompts user for package name

MENU_STRUCTURE = {
    "System Health": {
        "update": DnfCommand(
            "Update System", 
            "Upgrades all installed packages to the latest version.",
            ["dnf", "upgrade", "--refresh"]
        ),
        "cleanup": DnfCommand(
            "Update & Cleanup", 
            "Updates system and removes unused dependencies (autoremove).",
            ["dnf", "upgrade", "--refresh", "&&", "dnf", "autoremove"]
        ),
        "dependencies": DnfCommand(
            "Check Broken Dependencies",
            "Checks for package dependency problems.",
            ["dnf", "check"]
        ),
        "orphans": DnfCommand(
            "List Orphaned Packages",
            "Lists packages installed as dependencies but no longer needed.",
            ["dnf", "repoquery", "--unneeded", "--installed"]
        )
    },
    "Install / Remove": {
        "search": DnfCommand(
            "Search Packages",
            "Search repository metadata for a keyword.",
            ["dnf", "search"],
            input_required=True
        ),
        "install": DnfCommand(
            "Install Package",
            "Install a new package by name.",
            ["dnf", "install"],
            input_required=True
        ),
        "remove": DnfCommand(
            "Remove Package",
            "Uninstall a package.",
            ["dnf", "remove"],
            input_required=True,
            risky=True
        ),
        "history": DnfCommand(
            "Show Transaction History",
            "List past DNF operations.",
            ["dnf", "history"]
        )
    },
    "Repositories": {
        "list_repos": DnfCommand(
            "List Enabled Repositories",
            "Show currently active software sources.",
            ["dnf", "repolist"]
        ),
        "enable_fusion": DnfCommand(
            "Enable RPM Fusion (Free/Non-Free)",
            "Installs RPM Fusion repositories for multimedia codecs and drivers.",
            ["dnf", "install", "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm", "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"],
            risky=False
        )
    },
    "Power / Risky": {
        "clean_all": DnfCommand(
            "Clean All Caches",
            "Removes all cached metadata and packages to free space.",
            ["dnf", "clean", "all"]
        ),
        "distro_sync": DnfCommand(
            "Distro Sync",
            "Synchronizes installed packages to the latest available versions, downgrading if necessary.",
            ["dnf", "distro-sync"],
            risky=True
        ),
        "rollback": DnfCommand(
            "Undo Last Transaction",
            "Attempts to undo the very last DNF action.",
            ["dnf", "history", "undo", "last"],
            risky=True
        )
    }
}