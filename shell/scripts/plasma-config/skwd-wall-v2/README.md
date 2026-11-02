## skwd-wall-v2

Thx to [liixini](https://github.com/liixini) for the beautiful wallpaper switcher.

The configuration file is stored at `$HOME/.config/skwd-wall-v2/config.json`

A default config file is provided by us in order to make skwd-wall work flawlessly with our shell.

Following options are the most important changes done in our config.json

- Post processing command is set to use `caelestia-color` to apply wallpapers. As a result, `caelestia-color` generates colors for the shell and also applies wallpaper to quickshell wallpaper layer, plasma wallpaper plugin and lockscreen. Hence, skwd-wall does not own color generation for the shell. Color options under Nexus -> Appearance -> Colors are still valid.
    ```json
    "postProcessing": [
        {
            "command": "PATH=$HOME/.local/bin:$PATH caelestia-color wallpaper -f %thumb% -a %path%",
            "type": "all"
        }
    ]
    ```

- The "Who drives color" option in skwd-wall is set to skwd-wall itself. Although, it provides caelestia as an option, but due to runtime injection of the bin files for caelestia, skwd-wall failes to recognize caelestia-color in path from time to time. Hence, direct path is preferred (used in postProcessing)
    ```json
    "theme": {
        "authority": "skwd",
        "policy": "wallpaper"
    }
    ```
- The WlrLayer for skwd-paper-plugin is set to `background` to avoid conflict with shell desktop, which resides on `WlrLayer.Bottom`.
    ```json
    "paper": {
        "wallpaperLayer": "background"
    }
    ```