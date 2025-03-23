#!/bin/bash

while true; do
    cpu_threshold="10.0"
    average_seconds=5
    cpu_usage=$(echo "100-$(vmstat $average_seconds 2 | tail -1 | awk '{print $15}')" | bc)

    #Check the current governor for all CPUs
    current_governors=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor)

    if (( $(echo "$cpu_usage < $cpu_threshold" | bc -l) )); then
	if [[ ! "$current_governors" =~ "powersave" ]]; then
		echo "CPU: $cpu_usage. Powersave mode enabled."
        	echo "powersave" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
	fi
    else
	if [[ ! "$current_governors" =~ "performance" ]]; then
		echo "CPU: $cpu_usage. Performance mode enabled for the next 30 seconds."
        	echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
		sleep 30 #Keep performance mode enabled for a while before checking again
	else
		echo "CPU: $cpu_usage. Performance mode still enabled."
		sleep 30 
	fi
    fi
done
