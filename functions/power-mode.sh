#!/bin/bash

# Power modes as "<cpu governor> <wifi>", cycled in this order by "cycle"
STATES=(
	"powersave powersave"
	"powersave full"
	"schedutil powersave"
	"schedutil full"
)

IFACE=$(iw dev | awk '$1 == "Interface" { print $2; exit }')
GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
WIFI=$(iw dev "$IFACE" get power_save 2>/dev/null | awk '{ print ($3 == "on") ? "powersave" : "full" }')

if [[ "$1" == "cycle" ]]; then
	CURRENT=-1
	for i in "${!STATES[@]}"; do
		[[ "${STATES[$i]}" == "$GOVERNOR $WIFI" ]] && CURRENT=$i
	done
	read -r NEXT_GOVERNOR NEXT_WIFI <<< "${STATES[$(( (CURRENT + 1) % ${#STATES[@]} ))]}"

	sudo -n cpupower frequency-set -g "$NEXT_GOVERNOR"
	sudo -n iw dev "$IFACE" set power_save "$([[ "$NEXT_WIFI" == "powersave" ]] && echo on || echo off)"
fi

if [[ "$1" == "" ]]; then
	echo "wifi: ${WIFI:-n/a}"
fi
