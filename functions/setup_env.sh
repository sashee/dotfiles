set -Eeuo pipefail

eval `aws sts get-session-token --serial-number $(aws iam list-mfa-devices --user-name $(aws sts get-caller-identity | jq -r '.Arn | split("/")[1]')| jq -r '.MFADevices[0].SerialNumber') --token-code $2 | jq -r '"export AWS_ACCESS_KEY_ID=" + .Credentials.AccessKeyId, "export AWS_SECRET_ACCESS_KEY="+.Credentials.SecretAccessKey, "export AWS_SESSION_TOKEN="+.Credentials.SessionToken'`

eval `ssh-agent`

ssh-add <(aws --region eu-central-1 ssm get-parameter --name $1 --with-decryption | jq -r '.Parameter.Value' | sed 's/\\n/\n/g')

RC=$(([ -r ~/.bashrc ] && cat ~/.bashrc); echo 'PS1="\[\e[0;32m\]$ \[\e[m\]"')

bash --rcfile <(echo $RC)
