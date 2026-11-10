# Lunar zsh configuration - sourced from ~/.zshrc
# Prompt:   user@host:path(branch⚡) »
# Overrides go into ~/.zshrc after the "source" line.

# ---------------------------------------------------------------- history
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
[[ -d "${HISTFILE:h}" ]] || mkdir -p "${HISTFILE:h}"
HISTSIZE=50000
SAVEHIST=50000
setopt EXTENDED_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE \
       HIST_REDUCE_BLANKS HIST_VERIFY SHARE_HISTORY

# ---------------------------------------------------------------- options
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS PUSHD_SILENT \
       INTERACTIVE_COMMENTS NO_BEEP EXTENDED_GLOB PROMPT_SUBST \
       COMPLETE_IN_WORD ALWAYS_TO_END AUTO_MENU LIST_PACKED

# ---------------------------------------------------------------- completion
fpath=(/usr/share/zsh/site-functions $fpath)
autoload -Uz compinit
_lunar_zcompdump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump-$ZSH_VERSION"
[[ -d "${_lunar_zcompdump:h}" ]] || mkdir -p "${_lunar_zcompdump:h}"
compinit -d "$_lunar_zcompdump"
unset _lunar_zcompdump

# colours for file listings and the completion menu
if (( $+commands[dircolors] )); then
    eval "$(dircolors -b)"
fi
zmodload zsh/complist
zstyle ':completion:*' menu select                       # arrow-key grid menu
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"  # same colours as ls
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' special-dirs true
zstyle ':completion:*' squeeze-slashes true
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
zstyle ':completion:*:warnings' format '%F{red}-- no matches --%f'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/compcache"
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
# shift-tab walks backwards through the menu
bindkey -M menuselect '^[[Z' reverse-menu-complete

# ---------------------------------------------------------------- prompt
autoload -Uz vcs_info
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' unstagedstr '⚡'
zstyle ':vcs_info:git:*' stagedstr '⚡'
zstyle ':vcs_info:git:*' formats       '%F{208}(%b%u%c)%f'
zstyle ':vcs_info:git:*' actionformats '%F{208}(%b|%a%u%c)%f'

# ⚡ also for untracked files
zstyle ':vcs_info:git*+set-message:*' hooks lunar-untracked
+vi-lunar-untracked() {
    if [[ -z "${hook_com[unstaged]}${hook_com[staged]}" ]] \
        && [[ -n "$(git ls-files --others --exclude-standard --directory --no-empty-directory 2>/dev/null | head -n1)" ]]; then
        hook_com[unstaged]='⚡'
    fi
}

autoload -Uz add-zsh-hook
_lunar_precmd() { vcs_info }
add-zsh-hook precmd _lunar_precmd

PROMPT='%B%F{green}%n@%m%f%b:%F{magenta}%~%f${vcs_info_msg_0_} %F{red}»%f '
RPROMPT='%(?..%F{red}%?%f)'

# ---------------------------------------------------------------- key bindings
bindkey -e
bindkey '^[[H'    beginning-of-line        # Home
bindkey '^[[F'    end-of-line              # End
bindkey '^[[3~'   delete-char              # Delete
bindkey '^[[1;5C' forward-word             # Ctrl+Right
bindkey '^[[1;5D' backward-word            # Ctrl+Left
bindkey '^H'      backward-kill-word       # Ctrl+Backspace

# ---------------------------------------------------------------- aliases
# modern replacements
alias ls='lsd'
alias l='lsd -lFh'
alias ll='lsd -alFh'
alias la='lsd -A'
alias lt='lsd --tree --depth 2'
alias cat='bat --paging=never --style=plain'
alias df='duf'
alias top='btop'
alias htop='btop'
alias find-text='rg'

# safer defaults and colours
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -I'
alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias ip='ip -color=auto'
alias mkdir='mkdir -p'

# navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# system
alias update='sudo pacman -Syu'
# remove packages that were installed as dependencies and are no longer needed
cleanup() {
    local -a orphans
    orphans=(${(f)"$(pacman -Qtdq 2>/dev/null)"})
    if (( ${#orphans} == 0 )); then
        echo "No orphaned packages."
        return 0
    fi
    sudo pacman -Rns $orphans
}
alias mirrors='sudo reflector --protocol https --latest 20 --age 12 --sort rate --save /etc/pacman.d/mirrorlist'
alias jctl='journalctl -p 3 -xb'
alias please='sudo $(fc -ln -1)'
alias fetch='fastfetch'

# ---------------------------------------------------------------- tools
# z <dir>: jump to frequently used directories (zi = interactive with fzf)
(( $+commands[zoxide] )) && eval "$(zoxide init zsh)"

# fzf: Ctrl+R history, Ctrl+T files, Alt+C directories
[[ -r /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
[[ -r /usr/share/fzf/completion.zsh ]]   && source /usr/share/fzf/completion.zsh

# suggest the package that provides an unknown command
[[ -r /usr/share/doc/pkgfile/command-not-found.zsh ]] \
    && source /usr/share/doc/pkgfile/command-not-found.zsh

# ---------------------------------------------------------------- plugins
# autosuggestions: grey ghost text from history, accept with Right/End
[[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] \
    && source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# history substring search on Up/Down
if [[ -r /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh ]]; then
    source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
    bindkey '^[[A' history-substring-search-up
    bindkey '^[[B' history-substring-search-down
fi

# syntax highlighting must be sourced last
[[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] \
    && source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
