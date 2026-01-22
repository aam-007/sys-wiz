import sys
import os
import shutil
from syswiz.utils.system import is_fedora, ensure_sudo
from syswiz.app import SysWizApp

def main():
    # 1. Clear terminal for clean start
    os.system('cls' if os.name == 'nt' else 'clear')

    # 2. Check Distro
    if not is_fedora():
        print("Error: sys-wiz is designed strictly for Fedora Linux.")
        print("Safety Abort: Non-Fedora OS detected.")
        sys.exit(1)

    # 3. Check/Request Sudo (Plain English explanation)
    if not ensure_sudo():
        print("\n[!] Sudo authentication failed or was cancelled.")
        print("    sys-wiz cannot modify system packages without permissions.")
        print("    Exiting gracefully.")
        sys.exit(0)

    # 4. Launch TUI
    app = SysWizApp()
    app.run()

if __name__ == "__main__":
    main()