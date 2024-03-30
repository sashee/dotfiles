alias reload!='. ~/.zshrc'

alias cls='clear' # Good 'ol Clear Screen command
alias npm='firejail npm'
alias nvim='firejail nvim'
alias nix-shell='/usr/sbin/firejail --profile=/home/sashee/dotfiles/firejail/firejail.profile nix-shell'
alias make='/usr/sbin/firejail --profile=/home/sashee/dotfiles/firejail/firejail.profile make'
#alias git='/usr/sbin/firejail git'
alias lazygit='/usr/sbin/firejail --profile=git lazygit'
