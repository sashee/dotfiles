sudo apt install -y zsh curl

sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh | sed 's:env zsh -l::g' | sed 's:chsh -s .*$::g')"

mv ~/.zshrc.pre-oh-my-zsh ~/.zshrc
