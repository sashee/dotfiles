INSTANCE_ID=$(aws --region eu-central-1 ec2 describe-instances --filter "Name=tag:Name,Values=$1" --query "Reservations[].Instances[].InstanceId" --no-paginate | jq -r '.[0]')
INSTANCE_TYPE=$(aws --region eu-central-1 ec2 describe-instances --filter "Name=tag:Name,Values=$1" --query "Reservations[].Instances[].InstanceType" --no-paginate | jq -r '.[0]')

TERMINAL=$(tty)
CHOICE=$(dialog --clear --title "Instance type" --default-item "$INSTANCE_TYPE" --menu "" 15 40 6 "t3.nano" "t3.nano" "t3.micro" "t3.micro" "t3.small" "t3.small" "t3.medium" "t3.medium" "t3.large" "t3.large" 2>&1 >$TERMINAL)
clear

if [ -z "$CHOICE" ]
then
	exit 1
fi

if [ "$CHOICE" != "$INSTANCE_TYPE" ]
then
	aws --region eu-central-1 ec2 modify-instance-attribute --instance-id "$INSTANCE_ID" --instance-type "{\"Value\": \"$CHOICE\"}"
fi

aws --region eu-central-1 ec2 start-instances --instance-ids "$INSTANCE_ID"

aws --region eu-central-1 ec2 wait instance-running --instance-ids "$INSTANCE_ID"
