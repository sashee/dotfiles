#!/bin/bash

# Bluetooth headset mode: "music" (A2DP: good sound, no mic) or "call" (HFP: mic, worse sound).
# Requires WirePlumber's autoswitch to be off, otherwise opening a mic flips the mode on its own:
#   wpctl settings --save bluetooth.autoswitch-to-headset-profile false

read -r CARD PROFILE <<< "$(pactl list cards 2>/dev/null | awk '
	/^\tName: bluez_card\./ { card = $2 }
	card != "" && /^\tActive Profile:/ { print card, $3; exit }
')"

case "$PROFILE" in
	headset-head-unit*) MODE=call ;;
	a2dp-sink*) MODE=music ;;
	*) MODE=$PROFILE ;;
esac

if [[ "$1" == "toggle" && -n "$CARD" ]]; then
	pactl set-card-profile "$CARD" "$([[ "$MODE" == "call" ]] && echo a2dp-sink || echo headset-head-unit)"
fi

if [[ "$1" == "" ]]; then
	echo "bt: ${MODE:-n/a}"
fi
