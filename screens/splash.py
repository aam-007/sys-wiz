from textual.screen import Screen
from textual.widgets import Header, Footer, Static, Button
from textual.containers import Container
from syswiz.utils.system import get_system_info

ASCII_LOGO = """
 ::::::::  :::   :::  ::::::::                :::       ::: ::::::::::: ::::::::: 
:+:    :+: :+:   :+: :+:    :+:               :+:       :+:     :+:          :+:  
+:+         +:+ +:+  +:+                      +:+       +:+     +:+         +:+   
+#++:++#++   +#++:   +#++:++#++ +#++:++#++:++ +#+  +:+  +#+     +#+        +#+    
       +#+    +#+           +#+               +#+ +#+#+ +#+     +#+       +#+     
#+#    #+#    #+#    #+#    #+#                #+#+# #+#+#      #+#      #+#      
 ########     ###     ########                  ###   ###   ########### ######### 
"""

class SplashScreen(Screen):
    def compose(self):
        sys_info = get_system_info()
        
        yield Container(
            Static(ASCII_LOGO, classes="logo"),
            Static(f"sys-wiz v0.1.0 | Author: AAM-007 | repo: github.com/aam-007/sys-wiz", classes="meta"),
            Static("---", classes="separator"),
            Static(f"OS:  {sys_info.get('os')} {sys_info.get('os_version')}", classes="info"),
            Static(f"DNF: {sys_info.get('dnf_version')}", classes="info"),
            Static("---", classes="separator"),
            Static("A transparent, guided wizard for Fedora package management.", classes="desc"),
            Button("Press Enter to Continue", variant="primary", id="start_btn"),
            classes="splash_container"
        )

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "start_btn":
            self.app.push_screen("privilege_check")