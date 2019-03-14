dir=$(dirname "$BASH_SOURCE[0]");

STATE=$(aws --region eu-central-1 ec2 describe-instances --filter "Name=tag:Name,Values=$2" --query "Reservations[].Instances[].State.Name" --no-paginate | jq -r '.[0]')
if [ "$STATE" != "running" ]
then
	$dir/start_instance.sh $2 || exit
fi

while true ; do
	IP=$(aws --region eu-central-1 ec2 describe-instances --filter "Name=tag:Name,Values=$2" --query "Reservations[].Instances[].NetworkInterfaces[].PrivateIpAddresses[].Association.PublicIp" --no-paginate | jq -r '.[0]')

	mkdir -p $3
	watch "find $3 -maxdepth 1 -mindepth 1 -exec "$dir/transfer_files.sh" $1@$IP {} \; -exec rm -r {} \;" > /dev/null &
	pid=$!

        ssh -o "StrictHostKeyChecking no" -q -L 0.0.0.0:8080:localhost:8080 -L 0.0.0.0:3000:localhost:3000 -L 0.0.0.0:3001:localhost:3001 -L 0.0.0.0:8443:localhost:443 -L 0.0.0.0:35729:localhost:35729 -L 0.0.0.0:9229:localhost:9229 -L 0.0.0.0:5901:localhost:5901 -CtA $1@$IP AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN tmux new-session -A -s main
	kill $pid > /dev/null
        sleep 1;
done
# No true-color support in 1.3.2. Need to try again when a new version is released
# mosh --ssh="ssh -tA" ubuntu@test.myawsexperiments.com -- env AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN tmux new-session -A -s main
