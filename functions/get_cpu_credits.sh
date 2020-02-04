printf "%.0f/%d" "-1" "-1"
: '
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
CPU_POSITIVE_BALANCE=$(aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUCreditBalance --start-time $(date --iso-8601=seconds -d "10 mins ago") --end-time $(date --iso-8601=seconds) --period 300 --statistics Maximum --dimensions Name=InstanceId,Value=$INSTANCE_ID | jq '.Datapoints | sort_by(.Timestamp | fromdateiso8601) | .[-1].Maximum')
CPU_SURPLUS_BALANCE=$(aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUSurplusCreditBalance --start-time $(date --iso-8601=seconds -d "10 mins ago") --end-time $(date --iso-8601=seconds) --period 300 --statistics Maximum --dimensions Name=InstanceId,Value=$INSTANCE_ID | jq '.Datapoints | sort_by(.Timestamp | fromdateiso8601) | .[-1].Maximum')

CPU_BALANCE=$(echo "$CPU_POSITIVE_BALANCE - $CPU_SURPLUS_BALANCE" | bc)

INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type)

CPU_CREDITS_PER_HOUR=$(curl -s https://sashee.github.io/aws-data/burstable_instances_cpu_credit_per_hour.json | jq --arg instanceType "$INSTANCE_TYPE" '.[$instanceType]')

MAX_CREDITS=$(echo "$CPU_CREDITS_PER_HOUR * 24" | bc)

printf "%.0f/%d" "$CPU_BALANCE" "$MAX_CREDITS"
'
