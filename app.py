from textual.app import App, ComposeResult
from textual.screen import Screen
from textual.widgets import Header, Footer, ListView, ListItem, Label, Input, Static, Button
from textual.containers import Container, Vertical
from syswiz.dnf.definitions import MENU_STRUCTURE, DnfCommand
from syswiz.screens.splash import SplashScreen
from syswiz.screens.execution import ExecutionScreen
from syswiz.safety.guardrails import ensure_sudo

class PrivilegeScreen(Screen):
    """Intermediary screen to explain and acquire Sudo."""
    def compose(self):
        yield Container(
            Static("Privilege Escalation Required", classes="header"),
            Static("sys-wiz requires administrative privileges to manage packages.", classes="desc"),
            Static("We will now attempt to acquire 'sudo' rights.", classes="desc"),
            Button("Acquire Sudo", variant="primary", id="sudo_btn"),
            Button("Exit", variant="error", id="exit_btn"),
            classes="modal"
        )

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "exit_btn":
            self.app.exit()
        elif event.button.id == "sudo_btn":
            if ensure_sudo(self.app):
                self.app.push_screen("main_menu")
            else:
                self.mount(Static("[bold red]Sudo failed. Please run sys-wiz as root or ensure you have sudo rights.[/]", classes="error"))

class InputScreen(Screen):
    """Captures package names for install/search/remove."""
    def __init__(self, cmd_def, callback):
        super().__init__()
        self.cmd_def = cmd_def
        self.callback = callback

    def compose(self):
        yield Container(
            Static(f"Input required for: {self.cmd_def.title}", classes="header"),
            Static("Enter package name or keyword:", classes="label"),
            Input(placeholder="package-name", id="pkg_input"),
            Button("Continue", variant="primary", id="submit"),
            Button("Cancel", variant="error", id="cancel"),
            classes="modal"
        )

    def on_button_pressed(self, event):
        if event.button.id == "cancel":
            self.app.pop_screen()
        elif event.button.id == "submit":
            val = self.query_one("#pkg_input").value
            if val.strip():
                self.app.pop_screen()
                self.callback(val)

class MainMenu(Screen):
    """The hierarchical menu browser."""
    
    def __init__(self):
        super().__init__()
        self.current_menu = MENU_STRUCTURE
        self.breadcrumbs = [] # stack of keys

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        yield Container(
            Static("Main Menu", id="menu_title", classes="header"),
            ListView(id="menu_list"),
        )
        yield Footer()

    def on_mount(self):
        self.update_menu()

    def update_menu(self):
        list_view = self.query_one("#menu_list")
        list_view.clear()
        
        # Add "Back" if deep in menu
        if self.breadcrumbs:
            list_view.append(ListItem(Label(".. [Go Back]"), id="back"))

        # current_menu is either a dict (submenu) or definitions
        for key, value in self.current_menu.items():
            if isinstance(value, dict):
                # It's a category
                list_view.append(ListItem(Label(f"📂 {key}"), id=key))
            elif isinstance(value, DnfCommand):
                # It's a command
                icon = "⚠️ " if value.risky else "🔧 "
                list_view.append(ListItem(Label(f"{icon} {value.title}"), id=key))

        title = " > ".join(["Home"] + self.breadcrumbs)
        self.query_one("#menu_title").update(title)

    def on_list_view_selected(self, event: ListView.Selected):
        selected_id = event.item.id

        if selected_id == "back":
            self.breadcrumbs.pop()
            # Rebuild view based on breadcrumbs
            ptr = MENU_STRUCTURE
            for b in self.breadcrumbs:
                ptr = ptr[b]
            self.current_menu = ptr
            self.update_menu()
            return

        selected_obj = self.current_menu[selected_id]

        if isinstance(selected_obj, dict):
            # Enter Submenu
            self.breadcrumbs.append(selected_id)
            self.current_menu = selected_obj
            self.update_menu()
        elif isinstance(selected_obj, DnfCommand):
            # Execute Command logic
            self.trigger_command(selected_obj)

    def trigger_command(self, cmd_def: DnfCommand):
        if cmd_def.input_required:
            self.app.push_screen(InputScreen(cmd_def, lambda val: self.launch_exec(cmd_def, val)))
        else:
            self.launch_exec(cmd_def)

    def launch_exec(self, cmd_def, user_input=None):
        self.app.push_screen(ExecutionScreen(cmd_def, user_input))

class SysWizApp(App):
    CSS = """
    Screen { align: center middle; }
    .splash_container { width: 80%; height: 80%; border: solid green; align: center middle; }
    .logo { color: green; content-align: center center; }
    .code_block { background: $surface; color: $text; padding: 1; border: solid white; }
    .error { color: red; }
    #menu_list { height: auto; border: solid blue; margin: 1; }
    RichLog { height: 1fr; border: solid white; }
    """

    def on_mount(self):
        self.install_screen(SplashScreen(), name="splash")
        self.install_screen(PrivilegeScreen(), name="privilege_check")
        self.install_screen(MainMenu(), name="main_menu")
        self.push_screen("splash")

def main():
    app = SysWizApp()
    app.run()

if __name__ == "__main__":
    main()