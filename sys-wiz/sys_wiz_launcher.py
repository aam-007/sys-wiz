import sys
import os
from syswiz.utils.system import is_fedora, ensure_sudo
from syswiz.app import SysWizApp

def main():
    os.system('cls' if os.name == 'nt' else 'clear')
    if not is_fedora():
        print("Error: sys-wiz is designed strictly for Fedora Linux.")
        sys.exit(1)
    if not ensure_sudo():
        print("\n[!] Sudo authentication failed. Exiting.")
        sys.exit(0)
    app = SysWizApp()
    app.run()

if __name__ == "__main__":
    main()
