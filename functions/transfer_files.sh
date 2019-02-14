HOST=$1
shift
ssh $HOST 'mkdir -p /tmp/files'
scp $* $HOST:/tmp/files/
