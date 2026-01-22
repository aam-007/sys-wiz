import shutil
import subprocess
import os
import sys

def is_fedora() -> bool:
    try:
        with open("/etc/os-release") as f:
            return "ID=fedora" in f.read()
    except FileNotFoundError:
        return False

def get_distro_info() -> dict:
    info = {"os": "Unknown", "dnf": "Unknown"}
    
    # Get Fedora Version
    try:
        with open("/etc/fedora-release") as f:
            info["os"] = f.read().strip()
    except FileNotFoundError:
        info["os"] = "Fedora Linux (Unknown Version)"

    # Get DNF Version
    try:
        result = subprocess.run(["dnf", "--version"], capture_output=True, text=True)
        # usually first line is dnf version
        info["dnf"] = result.stdout.splitlines()[0].strip()
    except FileNotFoundError:
        info["dnf"] = "DNF Not Found"

    return info

def ensure_sudo() -> bool:
    """
    Ensures the user has sudo privileges cached. 
    Returns True if successful, False otherwise.
    """
    if os.geteuid() == 0:
        return True
        
    print(" [!] sys-wiz requires sudo privileges to manage packages.")
    print(" [!] Requesting sudo access now to cache credentials...")
    
    try:
        
        subprocess.check_call(["sudo", "-v"])
        return True
    except subprocess.CalledProcessError:
        return False