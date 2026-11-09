#!/usr/bin/env python3
"""Container health check: each selected Hokuyo topic delivers a scan within HEALTH_TIMEOUT."""
import os
import sys
import time

import rclpy
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import LaserScan

TOPIC = {'front': 'raw_scan_front', 'rear': 'raw_scan_rear'}


def main():
    sides = os.environ.get('HOKUYOS', 'front,rear').split(',')
    topics = [TOPIC[s.strip()] for s in sides if s.strip() in TOPIC]
    rclpy.init()
    node = rclpy.create_node('urg_health')
    seen = set()
    for t in topics:
        node.create_subscription(
            LaserScan, t, lambda _m, t=t: seen.add(t), qos_profile_sensor_data)
    end = time.monotonic() + float(os.environ.get('HEALTH_TIMEOUT', '5'))
    while time.monotonic() < end and len(seen) < len(topics):
        rclpy.spin_once(node, timeout_sec=0.1)
    missing = [t for t in topics if t not in seen]
    print('healthy' if not missing else 'no data on: ' + ', '.join(missing))
    return 1 if missing else 0


if __name__ == '__main__':
    sys.exit(main())
