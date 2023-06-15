#!/bin/bash

SYS_BRIGHTNESS=$(cat /sys/class/backlight/amdgpu_bl0/actual_brightness)
XRANDR_BRIGHTNESS=$(xrandr --verbose | awk '/Brightness/ { print $2; exit }')
XRANDR_GAMMA=$(xrandr --verbose | awk '/Gamma/ { print $2; exit }')

XRANDR_GAMMA_R=$(echo "result = 1 / $(echo "$XRANDR_GAMMA" | cut -d ":" -f 1); scale=1; (result + 0.05) / 1"|bc -l)
XRANDR_GAMMA_G=$(echo "result = 1 / $(echo "$XRANDR_GAMMA" | cut -d ":" -f 2); scale=1; (result + 0.05) / 1"|bc -l)
XRANDR_GAMMA_B=$(echo "result = 1 / $(echo "$XRANDR_GAMMA" | cut -d ":" -f 3); scale=1; (result + 0.05) / 1"|bc -l)
NIGHT=$(echo "$XRANDR_GAMMA_R!=1 || $XRANDR_GAMMA_G!=1 || $XRANDR_GAMMA_B!=1" | bc -l)

if [[ "$1" == "inc" ]]; then
	if (( $(echo "$XRANDR_BRIGHTNESS < 1"|bc -l) )); then
		xrandr --output eDP --brightness "$(echo "res=$XRANDR_BRIGHTNESS + 0.1;if(res>1)1 else res" | bc -l)" --gamma "$XRANDR_GAMMA_R:$XRANDR_GAMMA_G:$XRANDR_GAMMA_B"
	else
		xbacklight -inc 1
	fi
fi

if [[ "$1" == "dec" ]]; then
	if (( $(echo "$SYS_BRIGHTNESS == 0"|bc -l) )); then
		xrandr --output eDP --brightness "$(echo "res=$XRANDR_BRIGHTNESS - 0.1;if(res<0)0 else res" | bc -l)" --gamma "$XRANDR_GAMMA_R:$XRANDR_GAMMA_G:$XRANDR_GAMMA_B"
	else
		xbacklight -dec 1
	fi
fi

if [[ "$1" == "turn_nightlight" ]]; then
	if [[ "$NIGHT" == "1" ]]; then
		xrandr --output eDP --brightness "$XRANDR_BRIGHTNESS" --gamma "1.0:1.0:1.0"
	else
		xrandr --output eDP --brightness "$XRANDR_BRIGHTNESS" --gamma "1.0:0.8:0.7"
	fi
fi

if [[ "$1" == "" ]]; then
	echo "sys: $SYS_BRIGHTNESS xrandr: $XRANDR_BRIGHTNESS, N: $NIGHT"
fi

