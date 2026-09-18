if status is-interactive
    # Starship custom prompt
    command -v starship &> /dev/null && starship init fish | source

    # Direnv + Zoxide
    command -v direnv &> /dev/null && direnv hook fish | source
    command -v zoxide &> /dev/null && zoxide init fish --cmd cd | source

    # Better ls
    command -v eza &> /dev/null && alias ls='eza --icons --group-directories-first -1'

    # Abbrs
    abbr lg 'lazygit'
    abbr gd 'git diff'
    abbr ga 'git add .'
    abbr gc 'git commit -am'
    abbr gl 'git log'
    abbr gs 'git status'
    abbr gst 'git stash'
    abbr gsp 'git stash pop'
    abbr gp 'git push'
    abbr gpl 'git pull'
    abbr gsw 'git switch'
    abbr gsm 'git switch main'
    abbr gb 'git branch'
    abbr gbd 'git branch -d'
    abbr gco 'git checkout'
    abbr gsh 'git show'

    abbr l 'ls'
    abbr ll 'ls -l'
    abbr la 'ls -a'
    abbr lla 'ls -la'

    # Custom colors
    if isatty stdout
        cat ~/.cache/caelestia/terminal-sequences 2> /dev/null
    end

    # High-contrast, theme-aware fish syntax and pager colors
    set -g fish_color_normal normal
    set -g fish_color_command blue --bold
    set -g fish_color_keyword magenta
    set -g fish_color_quote green
    set -g fish_color_redirection magenta
    set -g fish_color_end blue
    set -g fish_color_error red --bold
    set -g fish_color_param normal
    set -g fish_color_comment brblack
    set -g fish_color_selection --reverse
    set -g fish_color_search_match --reverse
    set -g fish_color_operator cyan
    set -g fish_color_escape cyan
    set -g fish_color_autosuggestion 999
    set -g fish_color_cancel red --reverse
    set -g fish_color_cwd green
    set -g fish_color_user cyan
    set -g fish_color_host blue

    # Fish Tab Completion Pager Colors
    set -g fish_pager_color_progress brwhite --background=cyan
    set -g fish_pager_color_prefix cyan --underline
    set -g fish_pager_color_completion normal
    set -g fish_pager_color_description 999
    set -g fish_pager_color_selected_background --reverse
    set -g fish_pager_color_selected_prefix cyan --underline
    set -g fish_pager_color_selected_completion normal
    set -g fish_pager_color_selected_description 999
    set -g fish_pager_color_secondary_background
    set -g fish_pager_color_secondary_prefix cyan --underline
    set -g fish_pager_color_secondary_completion normal
    set -g fish_pager_color_secondary_description 999

    # For jumping between prompts in foot terminal
    function mark_prompt_start --on-event fish_prompt
        echo -en "\e]133;A\e\\"
    end

    # Custom fish config
    source ~/.config/caelestia/user-config.fish 2> /dev/null
end
