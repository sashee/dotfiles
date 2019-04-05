unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
CPU_BALANCE=$(aws --region $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | rev | cut -c 2- | rev) cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUCreditBalance --start-time $(date --iso-8601=seconds -d "10 mins ago") --end-time $(date --iso-8601=seconds) --period 1 --statistics Maximum --dimensions Name=InstanceId,Value=$(curl -s http://169.254.169.254/latest/meta-data/instance-id) | jq '.Datapoints[-1].Maximum')

printf "%.0f" "$CPU_BALANCE"
