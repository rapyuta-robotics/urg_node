#!/bin/bash
# urg_node hardware test image entrypoint.
#   (no args) | launch [launch args]   start the Hokuyo driver(s)
#   check [args]                       scan_check.py (rate, frame, inf/NaN encoding), exit 1 on FAIL
#   health                             container health check
#   version                            urg_node source commit and image version
#   run.sh                             print the host helper script (docker run --rm <image> run.sh > run.sh)
#   <command>                          run a command in the ROS environment
set -e
source "/opt/ros/${ROS_DISTRO}/setup.bash"
source /opt/urg/setup.bash

case "${1:-launch}" in
    launch)  shift || true; exec ros2 launch /opt/urg_hw/hokuyo.launch.py "$@" ;;
    check)   shift; exec python3 /opt/urg_hw/scan_check.py "$@" ;;
    health)  exec python3 /opt/urg_hw/scan_health.py ;;
    version) cat /opt/urg_hw/VERSION ;;
    run.sh)  sed "s|^IMAGE=.*|IMAGE=\${IMAGE:-${IMAGE_REF}}|" /opt/urg_hw/run.sh ;;
    *)       exec "$@" ;;
esac
