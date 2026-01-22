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
    Log { border: solid $secondary; background: $surface-darken-3; height: 1fr; }
    """
    def on_mount(self):
        self.install_screen(SplashScreen(), name="splash")
        self.install_screen(MainMenu(), name="main_menu")
        self.push_screen("splash")
