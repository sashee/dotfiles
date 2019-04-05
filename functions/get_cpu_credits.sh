unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
CPU_BALANCE=$(aws --region $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | rev | cut -c 2- | rev) cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUCreditBalance --start-time $(date --iso-8601=seconds -d "10 mins ago") --end-time $(date --iso-8601=seconds) --period 1 --statistics Maximum --dimensions Name=InstanceId,Value=$(curl -s http://169.254.169.254/latest/meta-data/instance-id) | jq '.Datapoints[-1].Maximum')

INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type)

CPU_CREDITS_PER_HOUR=$(curl -s https://sashee.github.io/aws-data/burstable_instances_cpu_credit_per_hour.json | jq --arg instanceType "$INSTANCE_TYPE" '.[$instanceType]')

MAX_CREDITS=$(echo "$CPU_CREDITS_PER_HOUR * 24" | bc)

printf "%.0f/$MAX_CREDITS" "$CPU_BALANCE"
