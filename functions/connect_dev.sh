dir=$(dirname "$BASH_SOURCE[0]");

function setup_sg () {
	SG=$(aws --region eu-central-1 ec2 describe-instances --filter "Name=tag:Name,Values=$1" --query "Reservations[].Instances[].SecurityGroups[].GroupId" --no-paginate | jq -r '.[0]')

	CIDRS=$(aws --region eu-central-1 ec2 describe-security-groups --group-ids $SG | jq -r '.SecurityGroups[].IpPermissions[].IpRanges[].CidrIp')

	MYIP=$(curl -s ifconfig.me)

	for ip in $CIDRS; do
		[ "$MYIP/32" != $ip ] && aws --region eu-central-1 ec2 revoke-security-group-ingress --group-id $SG --protocol tcp --port 22 --cidr $ip
	done

	[ -z $(echo "$CIDRS" | grep "$MYIP/32") ] && aws --region eu-central-1 ec2 authorize-security-group-ingress --group-id $SG --protocol tcp --port 22 --cidr $MYIP/32
}

STATE=$(aws --region eu-central-1 ec2 describe-instances --filter "Name=tag:Name,Values=$2" --query "Reservations[].Instances[].State.Name" --no-paginate | jq -r '.[0]')
if [ "$STATE" != "running" ]
then
	setup_sg $2
	$dir/start_instance.sh $2 || exit
fi

while true ; do
	setup_sg $2

	IP=$(aws --region eu-central-1 ec2 describe-instances --filter "Name=tag:Name,Values=$2" --query "Reservations[].Instances[].NetworkInterfaces[].PrivateIpAddresses[].Association.PublicIp" --no-paginate | jq -r '.[0]')

	mkdir -p $3
	watch "find $3 -maxdepth 1 -mindepth 1 -exec "$dir/transfer_files.sh" $1@$IP {} \; -exec rm -r {} \;" > /dev/null &
	pid=$!

        ssh -o "StrictHostKeyChecking no" -q -L 0.0.0.0:8080:localhost:8080 -L 0.0.0.0:3000:localhost:3000 -L 0.0.0.0:3001:localhost:3001 -L 0.0.0.0:8443:localhost:443 -L 0.0.0.0:35729:localhost:35729 -L 0.0.0.0:9229:localhost:9229 -L 0.0.0.0:5901:localhost:5901 -CtA $1@$IP AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN tmux new-session -A -s main
	kill $pid > /dev/null
        sleep 1;
done

