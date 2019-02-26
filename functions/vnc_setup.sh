RUNNING=$(ps aux | grep vncserver | grep -v grep)

if [ -z "$RUNNING" ]
then
	vncserver
fi

export DISPLAY=:1
