MEM_FREE=$(awk '/MemAvailable/{print $2 / 1000000}' /proc/meminfo)
MEM_TOTAL=$(awk '/MemTotal/{print $2 / 1000000}' /proc/meminfo)

MEM_USED=$(echo "$MEM_TOTAL - $MEM_FREE" | bc)

printf "%.1f/%.1f" "$MEM_USED" "$MEM_TOTAL"

