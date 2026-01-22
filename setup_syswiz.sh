#!/bin/bash

# sys-wiz Setup Script
# Creates project structure, writes source code, and sets up venv.

PROJECT_DIR="sys-wiz"
PYTHON_CMD="python3"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Sys-Wiz Auto-Setup ===${NC}"

# 1. Check Python Version
echo -e "${BLUE}[1/5] Checking Python version...${NC}"
if ! command -v $PYTHON_CMD &> /dev/null; then
    echo -e "${RED}Error: python3 could not be found.${NC}"
    exit 1
fi
# Simple version check (requires 3.11+)
PY_VER=$($PYTHON_CMD -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo "      Detected Python $PY_VER"

# 2. Create Directory Structure
echo -e "${BLUE}[2/5] Creating project structure at ./$PROJECT_DIR...${NC}"
mkdir -p "$PROJECT_DIR/syswiz/dnf"
mkdir -p "$PROJECT_DIR/syswiz/screens"
mkdir -p "$PROJECT_DIR/syswiz/utils"
touch "$PROJECT_DIR/syswiz/__init__.py"
touch "$PROJECT_DIR/syswiz/dnf/__init__.py"
touch "$PROJECT_DIR/syswiz/screens/__init__.py"
touch "$PROJECT_DIR/syswiz/utils/__init__.py"

# 3. Write Source Files
echo -e "${BLUE}[3/5] Writing Python source code...${NC}"

# --- pyproject.toml ---
cat > "$PROJECT_DIR/pyproject.toml" << 'EOF'
[project]
name = "sys-wiz"
version = "0.1.0"
description = "Transparent, guided DNF wizard for Fedora."
requires-python = ">=3.11"
dependencies = [
    "textual>=0.40.0",
]
EOF

# --- syswiz/utils/system.py ---
cat > "$PROJECT_DIR/syswiz/utils/system.py" << 'EOF'
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
    try:
        with open("/etc/fedora-release") as f:
            info["os"] = f.read().strip()
    except FileNotFoundError:
        info["os"] = "Fedora Linux (Unknown Version)"

    try:
        result = subprocess.run(["dnf", "--version"], capture_output=True, text=True)
        info["dnf"] = result.stdout.splitlines()[0].strip()
    except (FileNotFoundError, IndexError):
        info["dnf"] = "DNF Not Found"

    return info

def ensure_sudo() -> bool:
    if os.geteuid() == 0:
        return True
    print(" [!] sys-wiz requires sudo privileges to manage packages.")
    print(" [!] Requesting sudo access now to cache credentials...")
    try:
        subprocess.check_call(["sudo", "-v"])
        return True
    except subprocess.CalledProcessError:
        return False
EOF

# --- syswiz/dnf/definitions.py ---
cat > "$PROJECT_DIR/syswiz/dnf/definitions.py" << 'EOF'
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
EOF

# --- syswiz/app.py ---
cat > "$PROJECT_DIR/syswiz/app.py" << 'EOF'
import asyncio
import shlex
import subprocess
from textual.app import App, ComposeResult
from textual.containers import Container, Horizontal
from textual.widgets import Label, Button, Tree, Input, Log, Static
from textual.screen import Screen, ModalScreen
from textual import work
from syswiz.utils.system import get_distro_info
from syswiz.dnf.definitions import COMMANDS, CommandDef

class SplashScreen(Screen):
    def compose(self) -> ComposeResult:
        sys_info = get_distro_info()
        logo = r"""
 ::::::::  :::   :::  ::::::::                :::       ::: ::::::::::: ::::::::: 
:+:    :+: :+:   :+: :+:    :+:               :+:       :+:     :+:          :+:  
+:+         +:+ +:+  +:+                      +:+       +:+     +:+         +:+   
+#++:++#++   +#++:   +#++:++#++ +#++:++#++:++ +#+  +:+  +#+     +#+        +#+    
       +#+    +#+           +#+               +#+ +#+#+ +#+     +#+       +#+     
#+#    #+#    #+#    #+#    #+#                #+#+# #+#+#      #+#      #+#      
 ########     ###     ########                  ###   ###   ########### ######### 
        """
        yield Container(
            Static(logo, classes="logo"),
            Static(f"sys-wiz v0.1.0", classes="meta"),
            Static(f"{sys_info['os']}", classes="meta-fedora"),
            Static(f"{sys_info['dnf']}", classes="meta-dnf"),
            Static("\nTransparent, Guided Package Management.", classes="tagline"),
            Button("Initialize System Wizard", variant="primary", id="start"),
            id="splash_container"
        )
    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "start":
            self.app.push_screen("main_menu")

class InputRequestScreen(ModalScreen):
    def __init__(self, prompt: str, callback):
        super().__init__()
        self.prompt_text = prompt
        self.callback = callback
    def compose(self) -> ComposeResult:
        yield Container(
            Label(self.prompt_text, classes="modal-label"),
            Input(placeholder="Type here...", id="user_input"),
            Horizontal(
                Button("Confirm", variant="success", id="confirm"),
                Button("Cancel", variant="error", id="cancel"),
                classes="modal-buttons"
            ),
            id="modal_dialog"
        )
    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "cancel":
            self.dismiss()
        elif event.button.id == "confirm":
            val = self.query_one(Input).value
            if val.strip():
                self.dismiss()
                self.callback(val)

class PreviewScreen(Screen):
    def __init__(self, cmd_def: CommandDef, specific_cmd: str):
        super().__init__()
        self.cmd_def = cmd_def
        self.specific_cmd = specific_cmd
    def compose(self) -> ComposeResult:
        risk_class = "risky" if self.cmd_def.is_risky else "safe"
        yield Container(
            Label("EXECUTION PREVIEW", classes="header"),
            Static(f"Operation: {self.cmd_def.title}", classes=f"title {risk_class}"),
            Static(f"Description: {self.cmd_def.description}", classes="desc"),
            Static("Exact Command to Run:", classes="label"),
            Static(f"$ {self.specific_cmd}", classes="code-block"),
            Horizontal(
                Button("PROCEED", variant="success" if not self.cmd_def.is_risky else "warning", id="run"),
                Button("CANCEL", variant="primary", id="cancel"),
                classes="buttons"
            ),
            id="preview_container"
        )
    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "cancel":
            self.app.pop_screen()
        elif event.button.id == "run":
            self.app.push_screen(ExecutionScreen(self.specific_cmd))

class ExecutionScreen(Screen):
    def __init__(self, command: str):
        super().__init__()
        self.command = command
    def compose(self) -> ComposeResult:
        yield Container(
            Label(f"Running: {self.command}", classes="exec-header"),
            Log(id="output_log", highlight=True),
            Button("Back to Menu", id="back", disabled=True),
            id="exec_container"
        )
    def on_mount(self):
        self.run_process()
    @work(exclusive=True, thread=True)
    def run_process(self):
        log = self.query_one(Log)
        args = shlex.split(self.command)
        try:
            process = subprocess.Popen(
                args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1
            )
            with process.stdout:
                for line in iter(process.stdout.readline, ''):
                    self.app.call_from_thread(log.write, line.strip())
            return_code = process.wait()
            self.app.call_from_thread(self.finished, return_code)
        except Exception as e:
            self.app.call_from_thread(log.write, f"Error: {str(e)}")
            self.app.call_from_thread(self.finished, 1)
    def finished(self, code: int):
        log = self.query_one(Log)
        btn = self.query_one("#back", Button)
        btn.disabled = False
        if code == 0:
            log.write("\n[green]✓ Operation Successful.[/green]")
        else:
            log.write(f"\n[red]✗ Operation Failed (Exit Code: {code}).[/red]")
        log.write("\nClick 'Back to Menu' to continue.")
    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "back":
            self.app.pop_screen(); self.app.pop_screen()

class MainMenu(Screen):
    def compose(self) -> ComposeResult:
        tree: Tree[CommandDef] = Tree("System Wizard Operations")
        tree.root.expand()
        for category, cmds in COMMANDS.items():
            cat_node = tree.root.add(category, expand=True)
            for key, definition in cmds.items():
                label = definition.title
                if definition.is_risky: label += " [WARNING]"
                cat_node.add_leaf(label, data=definition)
        yield Container(
            Label("Select Operation", classes="menu-header"),
            tree,
            Button("Exit sys-wiz", variant="error", id="exit"),
            id="menu_container"
        )
    def on_tree_node_selected(self, event: Tree.NodeSelected):
        if not event.node.allow_expand:
            cmd_def = event.node.data
            if cmd_def.needs_input:
                self.app.push_screen(InputRequestScreen(cmd_def.input_prompt, lambda val: self.show_preview(cmd_def, val)))
            else:
                self.show_preview(cmd_def, None)
    def show_preview(self, cmd_def: CommandDef, user_input: str | None):
        final_cmd = cmd_def.command_template
        if user_input:
            safe_input = shlex.quote(user_input)
            final_cmd = final_cmd.format(safe_input)
        self.app.push_screen(PreviewScreen(cmd_def, final_cmd))
    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "exit":
            self.app.exit()

class SysWizApp(App):
    CSS = """
    Screen { align: center middle; background: $surface; }
    #splash_container { width: 80%; height: 80%; border: heavy $primary; align: center middle; }
    .logo { color: $accent; margin-bottom: 2; text-align: center; }
    .meta { color: $text-muted; text-align: center; }
    .meta-fedora { color: $secondary; text-align: center; text-style: bold; }
    .meta-dnf { color: $secondary; text-align: center; }
    .tagline { margin-top: 1; text-align: center; }
    #menu_container { width: 90%; height: 90%; }
    Tree { background: $panel; padding: 1; border: solid $primary; }
    #preview_container { width: 80%; height: auto; border: heavy $accent; padding: 2; }
    .title { text-style: bold; margin-bottom: 1; }
    .risky { color: $error; }
    .safe { color: $success; }
    .code-block { background: $boost; padding: 1; margin: 1 0; color: $secondary; border-left: thick $secondary; }
    .buttons { align: center middle; margin-top: 1; }
    Button { margin: 0 1; }
    #modal_dialog { width: 60%; height: auto; background: $panel; border: heavy $primary; padding: 2; }
    .modal-buttons { align: center middle; margin-top: 2; }
    #exec_container { width: 95%; height: 95%; }
    Log { border: solid $secondary; background: $surface-dark; height: 1fr; }
    """
    def on_mount(self):
        self.install_screen(SplashScreen(), name="splash")
        self.install_screen(MainMenu(), name="main_menu")
        self.push_screen("splash")
EOF

# --- sys_wiz_launcher.py ---
cat > "$PROJECT_DIR/sys_wiz_launcher.py" << 'EOF'
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
EOF

# 4. Setup Virtual Environment
echo -e "${BLUE}[4/5] Setting up virtual environment...${NC}"
cd "$PROJECT_DIR"
$PYTHON_CMD -m venv .venv
source .venv/bin/activate

# 5. Install Dependencies
echo -e "${BLUE}[5/5] Installing Textual...${NC}"
pip install textual

echo -e "${GREEN}=== Setup Complete ===${NC}"
echo "To run sys-wiz, execute the following:"
echo -e "${BLUE}cd $PROJECT_DIR${NC}"
echo -e "${BLUE}./.venv/bin/python sys_wiz_launcher.py${NC}"