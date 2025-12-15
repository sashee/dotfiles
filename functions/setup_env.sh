set -Eeuo pipefail

TOKEN_CODE=$2
PASSPHRASE=$3

AWSRESULTS=$(aws sts get-session-token --serial-number $(aws iam list-mfa-devices --user-name $(aws sts get-caller-identity | jq -r '.Arn | split("/")[1]')| jq -r '.MFADevices[0].SerialNumber') --token-code $TOKEN_CODE)

AWSKEYS=$(echo $AWSRESULTS | jq -r '"AWS_ACCESS_KEY_ID=" + .Credentials.AccessKeyId, "AWS_SECRET_ACCESS_KEY="+.Credentials.SecretAccessKey, "AWS_SESSION_TOKEN="+.Credentials.SessionToken' | gzip | gpg --cipher-algo AES256 --symmetric --batch --passphrase $PASSPHRASE --batch | base64 | tr -d '\n')

unset AWSRESULTS

RC=$(([ -r ~/.bashrc ] && cat ~/.bashrc); echo 'PS1="\[\e[0;32m\]$ \[\e[m\]"')

AWSKEYS=$AWSKEYS bash --rcfile <(echo $RC)
