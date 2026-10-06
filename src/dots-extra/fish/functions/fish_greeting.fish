function fish_greeting
    set_color blue
    echo '     ______           __          __  _       '
    echo '    / ____/___ ____  / /__  _____/ /_(_)___ _ '
    echo '   / /   / __ `/ _ \/ / _ \/ ___/ __/ / __ `/ '
    echo '  / /___/ /_/ /  __/ /  __(__  ) /_/ / /_/ /  '
    echo '  \____/\__,_/\___/_/\___/____/\__/_/\__,_/   '
    set_color normal
    command -v fastfetch &> /dev/null && fastfetch --key-padding-left 5
end
