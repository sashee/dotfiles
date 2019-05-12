HOST=$1
shift
ssh -o "StrictHostKeyChecking no" $HOST 'mkdir -p /tmp/files'
scp -o "StrictHostKeyChecking no" -r "$@" $HOST:/tmp/files/
