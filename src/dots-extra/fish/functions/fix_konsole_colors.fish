function fix_konsole_colors
    if test "$TERM" != "foot"
        # Parse Matugen.colorscheme for Konsole
        set colorscheme "$HOME/.local/share/konsole/Matugen.colorscheme"
        if not test -f "$colorscheme"
            set colorscheme "$HOME/.local/share/konsole/Matugen Alt.colorscheme"
        end
        if not test -f "$colorscheme"
            set colorscheme "$HOME/.local/share/konsole/MaterialYou.colorscheme"
        end
        if test -f "$colorscheme"
            # Get Foreground for Color16
            set fg (grep -A 1 "^\[Foreground\]" "$colorscheme" | grep "Color=" | cut -d '=' -f 2)
            # Get Color2 for Color17
            set c2 (grep -A 1 "^\[Color2\]" "$colorscheme" | grep "Color=" | cut -d '=' -f 2)
            # Get Color4 for Color18
            set c4 (grep -A 1 "^\[Color4\]" "$colorscheme" | grep "Color=" | cut -d '=' -f 2)
            
            if test -n "$fg" -a -n "$c2" -a -n "$c4"
                # Split by comma and convert R,G,B to #RRGGBB format for OSC 4
                set -l fg_arr (string split ',' $fg)
                set -l c2_arr (string split ',' $c2)
                set -l c4_arr (string split ',' $c4)
                
                set fg_hex (printf "#%02x%02x%02x" $fg_arr[1] $fg_arr[2] $fg_arr[3])
                set c2_hex (printf "#%02x%02x%02x" $c2_arr[1] $c2_arr[2] $c2_arr[3])
                set c4_hex (printf "#%02x%02x%02x" $c4_arr[1] $c4_arr[2] $c4_arr[3])
                
                # Emit OSC 4 to dynamically update Konsole's 256-color palette
                echo -en "\033]4;16;$fg_hex\033\\"
                echo -en "\033]4;17;$c2_hex\033\\"
                echo -en "\033]4;18;$c4_hex\033\\"
            end
        end
    end
end
