RUNNING=$(ps aux | grep vncserver | grep -v grep)

if [ -z "$RUNNING" ]
then
	vncserver -geometry 1280x720
fi

export DISPLAY=:1
