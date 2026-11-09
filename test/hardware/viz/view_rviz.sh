#!/bin/bash
# Open RViz2 on this machine for the urg_node test (both Hokuyos).
# Usage: ./view_rviz.sh [robot-ip] [domain]   (no robot-ip: multicast discovery only)
# The robot side must use the same domain with subnet discovery and this machine as a static peer:
#   export ROS_DOMAIN_ID=78 ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET ROS_STATIC_PEERS=<this-machine-ip>
set -eo pipefail
ROBOT_IP=${1:-}
DOMAIN=${2:-78}
HERE=$(cd "$(dirname "$0")" && pwd)
source /opt/ros/lyrical/setup.bash
# UDP only: shared memory with root-owned robot containers fails on one host and is unused across hosts
export ROS_DOMAIN_ID=$DOMAIN ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET FASTDDS_BUILTIN_TRANSPORTS=UDPv4
[[ -n "$ROBOT_IP" ]] && export ROS_STATIC_PEERS=$ROBOT_IP
MY_IP=$(ip -4 route get "${ROBOT_IP:-8.8.8.8}" 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="src") print $(i+1)}')
echo "RViz2: domain $DOMAIN, robot ${ROBOT_IP:-any (multicast)}, this machine $MY_IP"
echo "On the robot: export ROS_DOMAIN_ID=$DOMAIN ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET ROS_STATIC_PEERS=$MY_IP"
ros2 daemon stop >/dev/null 2>&1 || true
# X11 platform, no HiDPI scaling; NVIDIA PRIME offload only when an NVIDIA driver is present
export QT_SCREEN_SCALE_FACTORS=1 QT_ENABLE_HIGHDPI_SCALING=0 QT_QPA_PLATFORM=xcb
command -v nvidia-smi >/dev/null 2>&1 && export __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia
exec rviz2 -d "$HERE/urg_hokuyos.rviz"
