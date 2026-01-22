import shutil
import subprocess
import distro
import sys

def get_system_info():
    """Detects Fedora version and DNF version."""
    if not distro.id() == 'fedora':
        return {"error": "This tool is designed specifically for Fedora Linux."}

    fedora_ver = distro.version()
    
    try:
        dnf_out = subprocess.check_output(["dnf", "--version"], text=True)
        dnf_ver = dnf_out.splitlines()[0].split()[-1]
    except FileNotFoundError:
        return {"error": "DNF executable not found."}

    return {
        "os": "Fedora Linux",
        "os_version": fedora_ver,
        "dnf_version": dnf_ver,
        "user": "root" if is_root() else "user"
    }

def is_root():
    import os
    return os.geteuid() == 0