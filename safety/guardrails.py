import subprocess
import sys
from textual.app import App

def ensure_sudo(app: App) -> bool:
    """
    Attempts to cache sudo credentials via `sudo -v`.
    Returns True if successful, False otherwise.
    """
    try:
        subprocess.run(["sudo", "-v"], check=True, capture_output=True)
        return True
    except subprocess.CalledProcessError:
        return False
    except FileNotFoundError:
        return False