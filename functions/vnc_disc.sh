RUNNING=$(ps aux | grep vncserver | grep -v grep)

if ! [ -z "$RUNNING" ]
then
	vncserver -kill
fi

unset DISPLAY

