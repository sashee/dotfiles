TMPDIR=$(dirname $(mktemp -u))
COMMAND=$1
COMMANDTMP="$TMPDIR/$COMMAND"

mkdir -p "$COMMANDTMP"

[ -f "$COMMANDTMP/result" ] && cat "$COMMANDTMP/result" || echo "$2"

$COMMAND > "$TMPDIR/$COMMAND/result" &>/dev/null &

