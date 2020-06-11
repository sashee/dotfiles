#!/bin/bash

# RC=$(([ -r ~/.bashrc  ] && cat ~/.bashrc); echo -n 'export PS1="$ "')
RC=$(echo 'export PS1="$ "; export RECORDING_MODE=true; watch echo "Set to ~100x26. Current dimensions: \$(tput cols)x\$(tput lines)"')

tmux set -g status off
echo -ne "\\ePtmux;\\e\\033]11;#fdf6e3\\007\\e\\\\"

bash --rcfile <(echo $RC)
echo -ne "\\ePtmux;\\e\\033]11;#000000\\007\\e\\\\"

tmux set -g status on

watch echo "Set to ~174x46. Current dimensions: \$(tput cols)x\$(tput lines)"
