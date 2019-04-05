echo "$(awk '/MemAvailable/{printf "%.1f", $2 / 1000000}' /proc/meminfo)/$(awk '/MemTotal/{printf "%.1f", $2 / 1000000}' /proc/meminfo)"

