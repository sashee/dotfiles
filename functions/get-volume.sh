#!/bin/bash

VOLUME=$(pactl list sinks | grep '^[[:space:]]Volume:' | \
	head -n $(( $SINK + 1 )) | tail -n 1 | sed -e 's,.* \([0-9][0-9]*\)%.*,\1,')

MUTED=$(pactl get-sink-mute @DEFAULT_SINK@ | awk '{print $NF == "yes"}')

if [[ "$MUTED" == "1" ]];
then
	echo "<fc=#FF5050>$VOLUME%</fc>"
else
	echo "$VOLUME%"
fi

