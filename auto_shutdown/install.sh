if $(curl -s -m 5 http://169.254.169.254/latest/dynamic/instance-identity/document | grep -q availabilityZone) ; then
	cat auto_shutdown/shutdown_if_no_sessions.timer | envsubst | sudo tee /etc/systemd/system/shutdown_if_no_sessions.timer > /dev/null

	cat auto_shutdown/shutdown_if_no_sessions.service | USERNAME="$(id -u -n)" GROUPNAME="$(id -g -n)" envsubst | \
		sudo tee /etc/systemd/system/shutdown_if_no_sessions.service > /dev/null

	sudo systemctl enable shutdown_if_no_sessions.timer
	sudo systemctl start shutdown_if_no_sessions.timer
fi
