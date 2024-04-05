alias reload!='. ~/.zshrc'

alias cls='clear' # Good 'ol Clear Screen command
alias npm='firejail --rmenv=AWSKEYS npm'
alias npx='firejail --rmenv=AWSKEYS npx'
alias nvim='firejail --rmenv=AWSKEYS --noblacklist=/tmp/tmux-1000 nvim'
alias nix-shell='/usr/sbin/firejail --rmenv=AWSKEYS --profile=/home/sashee/dotfiles/firejail/firejail.profile nix-shell'
alias make='/usr/sbin/firejail --rmenv=AWSKEYS --profile=/home/sashee/dotfiles/firejail/firejail.profile make'
#alias git='/usr/sbin/firejail git'
alias lazygit='/usr/sbin/firejail --rmenv=AWSKEYS --profile=git lazygit'
