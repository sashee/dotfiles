INSTANCE_ID=$(aws --region eu-central-1 ec2 describe-instances --filter "Name=tag:Name,Values=$1" --query "Reservations[].Instances[].InstanceId" --no-paginate | jq -r '.[0]')

aws --region eu-central-1 ec2 stop-instances --instance-ids "$INSTANCE_ID"

aws --region eu-central-1 ec2 wait instance-stopped --instance-ids "$INSTANCE_ID"
