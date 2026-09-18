function fish_greeting
    set_color blue
    echo '   _____            _           _   _'
    echo '  / ____|          | |         | | (_)'
    echo ' | |     __ _  ___ | | ___  ___| |_ _  __ _'
    echo ' | |    / _` |/ _ \| |/ _ \/ __| __| |/ _` |'
    echo ' | |___| (_| | (_) | |  __/\__ \ |_| | (_| |'
    echo '  \_____\__,_|\___/|_|\___||___/\__|_|\__,_|'
    set_color normal
    command -v fastfetch &> /dev/null && fastfetch --key-padding-left 5
end
