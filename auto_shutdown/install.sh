if $(curl -s -m 5 http://169.254.169.254/latest/dynamic/instance-identity/document | grep -q availabilityZone) ; then
	sudo cp auto_shutdown/shutdown_if_no_sessions /etc/cron.hourly/

	sudo chown root:root /etc/cron.hourly/shutdown_if_no_sessions
fi
