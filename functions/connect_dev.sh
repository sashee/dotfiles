dir=$(dirname "$BASH_SOURCE[0]");

PASSPHRASE="$4"

SG=$(aws --region eu-central-1 ec2 describe-instances --filter "Name=tag:Name,Values=$2" --query "Reservations[].Instances[].SecurityGroups[].GroupId" --no-paginate | jq -r '.[0]')

while : ; do
	MYIP=$(curl -s ifconfig.me)
	[ -z "$MYIP" ] && MYIP=$(curl -s ifconfig.co)
	[ -z "$MYIP" ] || break
done

function setup_sg () {
	CIDRS=$(aws --region eu-central-1 ec2 describe-security-groups --group-ids $1 | jq -r '.SecurityGroups[].IpPermissions[] | select(.FromPort == 22 and .ToPort == 22) | .IpRanges[].CidrIp')

	for ip in $CIDRS; do
		[ "$2/32" != $ip ] && aws --region eu-central-1 ec2 revoke-security-group-ingress --group-id $1 --protocol tcp --port 22 --cidr $ip
	done

	[ -z $(echo "$CIDRS" | grep "$2/32") ] && aws --region eu-central-1 ec2 authorize-security-group-ingress --group-id $1 --protocol tcp --port 22 --cidr $2/32
}

setup_sg $SG $MYIP

STATE=$(aws --region eu-central-1 ec2 describe-instances --filter "Name=tag:Name,Values=$2" --query "Reservations[].Instances[].State.Name" --no-paginate | jq -r '.[0]')
if [ "$STATE" != "running" ]
then
	$dir/start_instance.sh $2 || exit
fi

while true ; do
	while : ; do
		CURRENTMYIP=$(curl -s ifconfig.me)
		[ -z "$CURRENTMYIP" ] && CURRENTMYIP=$(curl -s ifconfig.co)
		[ -z "$CURRENTMYIP" ] || break
		sleep 1
	done

	[ "$CURRENTMYIP" != "$MYIP" ] && setup_sg $SG $CURRENTMYIP
	MYIP="$CURRENTMYIP"

	IP=$(aws --region eu-central-1 ec2 describe-instances --filter "Name=tag:Name,Values=$2" --query "Reservations[].Instances[].NetworkInterfaces[].PrivateIpAddresses[].Association.PublicIp" --no-paginate | jq -r '.[0]')

	mkdir -p $3
	trap 'kill $(jobs -p) 2> /dev/null' EXIT
	watch "find $3 -maxdepth 1 -mindepth 1 -exec "$dir/transfer_files.sh" $1@$IP {} \; -exec rm -r {} \;" > /dev/null &
	AWSKEYS=$(echo "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN" | gzip | gpg --cipher-algo AES256 --symmetric --passphrase $PASSPHRASE --batch | base64 | tr -d '\n')

	echo "Connecting" 
	ssh -q -o ConnectTimeout=10 -o "StrictHostKeyChecking no" -L 0.0.0.0:8080:localhost:8080 -L 0.0.0.0:3000:localhost:3000 -L 0.0.0.0:3001:localhost:3001 -L 0.0.0.0:8443:localhost:443 -L 0.0.0.0:35729:localhost:35729 -L 0.0.0.0:9229:localhost:9229 -L 0.0.0.0:5901:localhost:5901 -L 0.0.0.0:4200:localhost:4200 -L 0.0.0.0:4001:localhost:4001 -CtA $1@$IP AWSKEYS="$AWSKEYS" TZ=$(getprop persist.sys.timezone) tmux new-session -A -s main
	clear;
	echo "Connection closed"
	kill $(jobs -p) 2> /dev/null
        sleep 1;
done

