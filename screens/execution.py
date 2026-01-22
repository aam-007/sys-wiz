from textual.screen import Screen
from textual.widgets import Static, Button, RichLog, Input
from textual.containers import Vertical, Horizontal
from textual import work
import subprocess
import shlex

class ExecutionScreen(Screen):
    def __init__(self, command_def, user_input=None):
        super().__init__()
        self.cmd_def = command_def
        self.user_input = user_input
        self.full_command = list(self.cmd_def.cmd)
        
        if self.user_input:
            self.full_command.append(self.user_input)

        # Prepend sudo if not running as root, assuming sudo -v passed
        self.final_cmd_str = "sudo " + shlex.join(self.full_command)

    def compose(self):
        yield Vertical(
            Static(f"Operation: {self.cmd_def.title}", classes="header"),
            Static(self.cmd_def.description, classes="description"),
            Static("---", classes="sep"),
            Static("EXECUTABLE COMMAND:", classes="label"),
            Static(f"$ {self.final_cmd_str}", classes="code_block"),
            Static("---", classes="sep"),
            RichLog(id="output_log", highlight=True, markup=True),
            Horizontal(
                Button("Cancel / Back", variant="error", id="cancel"),
                Button("Proceed", variant="success", id="proceed"),
                classes="buttons"
            ),
            classes="exec_container"
        )

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "cancel":
            self.app.pop_screen()
        elif event.button.id == "proceed":
            self.query_one("#proceed").disabled = True
            self.query_one("#cancel").disabled = True
            self.run_process()

    @work(exclusive=True, thread=True)
    def run_process(self):
        log = self.query_one("#output_log")
        log.write(f"[bold green]Starting execution...[/]\n")
        
        # We assume sudo is cached or we are root
        cmd_list = ["sudo"] + self.full_command

        try:
            # shell=False for safety, merging stderr to stdout
            process = subprocess.Popen(
                cmd_list,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )

            for line in process.stdout:
                log.write(line.strip())

            process.wait()

            if process.returncode == 0:
                log.write(f"\n[bold green]SUCCESS: Operation completed.[/]")
            else:
                log.write(f"\n[bold red]FAILURE: Process exited with code {process.returncode}[/]")

        except Exception as e:
            log.write(f"\n[bold red]ERROR: {str(e)}[/]")

        # Enable back button, keep proceed disabled
        self.app.call_from_thread(self.enable_back)

    def enable_back(self):
        self.query_one("#cancel").label = "Back to Menu"
        self.query_one("#cancel").disabled = False