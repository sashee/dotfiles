HOST=$1
shift
ssh $HOST 'mkdir -p /tmp/files'
scp -r "$@" $HOST:/tmp/files/
