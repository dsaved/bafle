#!/usr/bin/env bash
# setup-environment.sh - Create environment configuration files
# This script creates /usr/etc/profile and /usr/etc/bash.bashrc for the bootstrap

set -e

BOOTSTRAP_DIR="${BOOTSTRAP_DIR:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create /usr/etc/profile
create_profile() {
    local etc_dir="$BOOTSTRAP_DIR/usr/etc"
    local profile_file="$etc_dir/profile"
    
    log_info "Creating $profile_file..."
    
    cat > "$profile_file" << 'EOF'
# /usr/etc/profile - System-wide environment configuration
# This file is sourced by all POSIX-compatible shells

# Set default PATH
export PATH="/usr/bin:/usr/sbin:/bin:/sbin"

# Set default umask
umask 022

# Set default editor
export EDITOR=vi
export VISUAL=vi

# Set locale
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# Set terminal type
export TERM="${TERM:-xterm-256color}"

# Set home directory if not set
if [ -z "$HOME" ]; then
    export HOME="/root"
fi

# Set user if not set
if [ -z "$USER" ]; then
    export USER="$(whoami 2>/dev/null || echo root)"
fi

# Set hostname if not set
if [ -z "$HOSTNAME" ]; then
    export HOSTNAME="$(hostname 2>/dev/null || echo localhost)"
fi

# Set PS1 for POSIX shells
if [ -z "$PS1" ]; then
    if [ "$USER" = "root" ]; then
        PS1='# '
    else
        PS1='$ '
    fi
    export PS1
fi

# Source user profile if it exists
if [ -f "$HOME/.profile" ]; then
    . "$HOME/.profile"
fi

# Source profile.d scripts if directory exists
if [ -d /usr/etc/profile.d ]; then
    for script in /usr/etc/profile.d/*.sh; do
        if [ -r "$script" ]; then
            . "$script"
        fi
    done
    unset script
fi
EOF
    
    chmod 644 "$profile_file"
    log_success "Created profile"
}

# Create /usr/etc/bash.bashrc
create_bash_bashrc() {
    local etc_dir="$BOOTSTRAP_DIR/usr/etc"
    local bashrc_file="$etc_dir/bash.bashrc"
    
    log_info "Creating $bashrc_file..."
    
    cat > "$bashrc_file" << 'EOF'
# /usr/etc/bash.bashrc - System-wide bash configuration
# This file is sourced by interactive bash shells

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Set default PATH
export PATH="/usr/bin:/usr/sbin:/bin:/sbin"

# Set locale
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# Set terminal type
export TERM="${TERM:-xterm-256color}"

# History settings
export HISTSIZE=1000
export HISTFILESIZE=2000
export HISTCONTROL=ignoreboth:erasedups
shopt -s histappend

# Check window size after each command
shopt -s checkwinsize

# Enable extended pattern matching
shopt -s extglob

# Enable recursive globbing with **
shopt -s globstar 2>/dev/null || true

# Make less more friendly for non-text input files
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# Set colorful prompt
if [ -n "$BASH_VERSION" ]; then
    # Color definitions
    COLOR_RESET='\[\033[0m\]'
    COLOR_RED='\[\033[0;31m\]'
    COLOR_GREEN='\[\033[0;32m\]'
    COLOR_YELLOW='\[\033[0;33m\]'
    COLOR_BLUE='\[\033[0;34m\]'
    COLOR_PURPLE='\[\033[0;35m\]'
    COLOR_CYAN='\[\033[0;36m\]'
    COLOR_WHITE='\[\033[0;37m\]'
    
    # Set prompt based on user
    if [ "$USER" = "root" ] || [ "$UID" = "0" ]; then
        PS1="${COLOR_RED}\u${COLOR_RESET}@${COLOR_GREEN}\h${COLOR_RESET}:${COLOR_BLUE}\w${COLOR_RESET}# "
    else
        PS1="${COLOR_GREEN}\u${COLOR_RESET}@${COLOR_CYAN}\h${COLOR_RESET}:${COLOR_BLUE}\w${COLOR_RESET}\$ "
    fi
    export PS1
fi

# Enable color support for ls and grep
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# Common aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Safety aliases
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Utility aliases
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Enable programmable completion features
if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
fi

# Source user bashrc if it exists
if [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi

# Source bash completion scripts if directory exists
if [ -d /usr/etc/bash_completion.d ]; then
    for script in /usr/etc/bash_completion.d/*; do
        if [ -r "$script" ]; then
            . "$script"
        fi
    done
    unset script
fi
EOF
    
    chmod 644 "$bashrc_file"
    log_success "Created bash.bashrc"
}

# Create /usr/etc/inputrc
create_inputrc() {
    local etc_dir="$BOOTSTRAP_DIR/usr/etc"
    local inputrc_file="$etc_dir/inputrc"
    
    log_info "Creating $inputrc_file..."
    
    cat > "$inputrc_file" << 'EOF'
# /usr/etc/inputrc - Readline configuration
# This file controls the behavior of line input editing for programs using readline

# Enable 8-bit input
set meta-flag on
set input-meta on
set output-meta on
set convert-meta off

# Enable colored completion
set colored-stats on
set colored-completion-prefix on

# Show all completions immediately
set show-all-if-ambiguous on
set show-all-if-unmodified on

# Case-insensitive completion
set completion-ignore-case on

# Treat hyphens and underscores as equivalent
set completion-map-case on

# Show file type indicators
set visible-stats on
set mark-symlinked-directories on

# Enable menu completion
set menu-complete-display-prefix on

# History search with arrow keys
"\e[A": history-search-backward
"\e[B": history-search-forward

# Ctrl+Left/Right to move by word
"\e[1;5C": forward-word
"\e[1;5D": backward-word

# Home and End keys
"\e[H": beginning-of-line
"\e[F": end-of-line

# Delete key
"\e[3~": delete-char

# Page Up/Down for history
"\e[5~": history-search-backward
"\e[6~": history-search-forward
EOF
    
    chmod 644 "$inputrc_file"
    log_success "Created inputrc"
}

# Create /usr/etc/motd (Message of the Day)
create_motd() {
    local etc_dir="$BOOTSTRAP_DIR/usr/etc"
    local motd_file="$etc_dir/motd"
    
    log_info "Creating $motd_file..."
    
    cat > "$motd_file" << 'EOF'
Welcome to the PRoot-compatible Bootstrap Environment!

This is a minimal Linux environment designed to run in PRoot.

For more information, visit: https://github.com/dsaved/bafle

EOF
    
    chmod 644 "$motd_file"
    log_success "Created motd"
}

# Create profile.d directory
create_profile_d() {
    local profile_d_dir="$BOOTSTRAP_DIR/usr/etc/profile.d"
    
    log_info "Creating profile.d directory..."
    
    mkdir -p "$profile_d_dir"
    chmod 755 "$profile_d_dir"
    
    # Create a sample profile.d script
    cat > "$profile_d_dir/00-bootstrap.sh" << 'EOF'
# Bootstrap environment initialization

# Set bootstrap root if not set
if [ -z "$BOOTSTRAP_ROOT" ]; then
    export BOOTSTRAP_ROOT="/usr"
fi

# Add bootstrap bin to PATH if not already there
case ":$PATH:" in
    *:/usr/bin:*) ;;
    *) export PATH="/usr/bin:$PATH" ;;
esac
EOF
    
    chmod 644 "$profile_d_dir/00-bootstrap.sh"
    log_success "Created profile.d directory"
}

# Create bash_completion.d directory
create_bash_completion_d() {
    local completion_d_dir="$BOOTSTRAP_DIR/usr/etc/bash_completion.d"
    
    log_info "Creating bash_completion.d directory..."
    
    mkdir -p "$completion_d_dir"
    chmod 755 "$completion_d_dir"
    
    log_success "Created bash_completion.d directory"
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [BOOTSTRAP_DIR]

Create environment configuration files in the bootstrap directory.

Arguments:
  BOOTSTRAP_DIR         Path to bootstrap directory (can also use BOOTSTRAP_DIR env var)

Environment Variables:
  BOOTSTRAP_DIR         Bootstrap directory path

Examples:
  $0 /path/to/bootstrap
  BOOTSTRAP_DIR=/path/to/bootstrap $0

EOF
}

# Main function
main() {
    # Get bootstrap directory from argument or environment
    if [ $# -gt 0 ]; then
        BOOTSTRAP_DIR="$1"
    fi
    
    # Validate bootstrap directory
    if [ -z "$BOOTSTRAP_DIR" ]; then
        log_error "Bootstrap directory not specified"
        show_usage
        exit 1
    fi
    
    if [ ! -d "$BOOTSTRAP_DIR" ]; then
        log_error "Bootstrap directory not found: $BOOTSTRAP_DIR"
        exit 1
    fi
    
    # Ensure etc directory exists
    local etc_dir="$BOOTSTRAP_DIR/usr/etc"
    if [ ! -d "$etc_dir" ]; then
        log_error "etc directory not found: $etc_dir"
        exit 1
    fi
    
    log_info "Setting up environment in: $BOOTSTRAP_DIR"
    echo ""
    
    # Create all environment files
    create_profile
    echo ""
    
    create_bash_bashrc
    echo ""
    
    create_inputrc
    echo ""
    
    create_motd
    echo ""
    
    create_profile_d
    echo ""
    
    create_bash_completion_d
    echo ""
    
    log_success "Environment setup completed"
}

# Run main function
main "$@"
