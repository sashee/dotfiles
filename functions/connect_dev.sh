while true ; do
	dir=$(dirname "$BASH_SOURCE[0]");
	mkdir -p $2
	watch "find $2 -maxdepth 1 -mindepth 1 -exec "$dir/transfer_files.sh" $1 {} \; -exec rm -r {} \;" > /dev/null &
	pid=$!
        XPORT=$((netstat -nutlp 2> /dev/null | grep :600 | awk '{print $4}' | awk -F: '{print $2}' ; echo 6000) | sort | tail -1)
        ssh -CtA $1 AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN tmux new-session -A -s main
	kill $pid > /dev/null
        sleep 1;
done
# No true-color support in 1.3.2. Need to try again when a new version is released
# mosh --ssh="ssh -tA" ubuntu@test.myawsexperiments.com -- env AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN tmux new-session -A -s main
