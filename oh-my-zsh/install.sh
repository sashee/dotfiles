sudo apt install -y zsh curl

sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh | sed 's:env zsh -l::g' | sed 's:chsh -s .*$::g')"

if [ -e ~/.zshrc.pre-oh-my-zsh ]; then
	mv ~/.zshrc.pre-oh-my-zsh ~/.zshrc
fi

sudo apt install -y locales
sudo locale-gen en_US.UTF-8
