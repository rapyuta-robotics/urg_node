#!/bin/bash
# Check the Hokuyo scans from THIS machine (over the network, as RViz receives them).
# Usage: ./stream_check.sh [robot-ip] [domain] [secs]
set -eo pipefail
ROBOT_IP=${1:-172.16.9.103}; DOMAIN=${2:-78}; SECS=${3:-10}
source /opt/ros/lyrical/setup.bash
export ROS_DOMAIN_ID=$DOMAIN ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET FASTDDS_BUILTIN_TRANSPORTS=UDPv4 ROS_STATIC_PEERS=$ROBOT_IP
ros2 daemon stop >/dev/null 2>&1 || true
for t in raw_scan_front raw_scan_rear; do
    printf '%-16s rate ' "$t"
    timeout "$SECS" ros2 topic hz "/$t" --qos-reliability best_effort 2>/dev/null | awk '/average rate/{r=$3} END{printf "%s", (r ? r " Hz" : "NO DATA")}' || true
    printf '   bandwidth '
    timeout 5 ros2 topic bw "/$t" --qos-reliability best_effort 2>/dev/null | awk '/B\/s from/{b=$1" "$2} END{print (b ? b : "-")}' || true
done
