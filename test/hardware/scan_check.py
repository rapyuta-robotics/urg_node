#!/usr/bin/env python3
"""
Check the Hokuyo scans of this urg_node against the ROS 1 PA-AMR behaviour.

Usage: scan_check.py [--secs N] [--expect-inf true|false|auto] [topic ...]
Default topics come from HOKUYOS (raw_scan_front, raw_scan_rear).
--expect-inf auto reads NO_RANGE_AS_INF.

Per topic it prints rate, frame_id, angles, beam count and how the no-return beams are
encoded (+inf, NaN, 0, finite). Checks (exit 1 if any fails):
  rate        35..45 Hz (UST-10LX/20LX: 40 Hz)
  frame_id    ends with scan_front_link / scan_rear_link
  intensities present (publish_intensity true, as in ROS 1)
  encoding    no_range_as_inf true  -> no NaN, no zero, no finite value outside
                                       [range_min, range_max]
              no_range_as_inf false -> no +inf (upstream behaviour)
"""
import argparse
import math
import os
import sys
import time

import rclpy
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import LaserScan

TOPIC = {'front': 'raw_scan_front', 'rear': 'raw_scan_rear'}
FRAME = {'raw_scan_front': 'scan_front_link', 'raw_scan_rear': 'scan_rear_link'}


def _true(v):
    return str(v).strip().lower() in ('1', 'true', 'yes', 'on')


class Stats:

    def __init__(self):
        self.stamps = []
        self.last = None
        self.inf = self.nan = self.zero = self.finite = self.out_of_range = 0
        self.min_r = math.inf
        self.max_r = 0.0

    def add(self, msg):
        self.stamps.append(time.monotonic())
        self.last = msg
        for r in msg.ranges:
            if math.isnan(r):
                self.nan += 1
            elif math.isinf(r):
                self.inf += 1
            elif r == 0.0:
                self.zero += 1
            else:
                self.finite += 1
                self.min_r = min(self.min_r, r)
                self.max_r = max(self.max_r, r)
                if r < msg.range_min or r > msg.range_max:
                    self.out_of_range += 1


def _report(topic, s, expect_inf):
    """Print the statistics of one topic and return True if every check passes."""
    if s.last is None:
        print('\n%s: NO DATA' % topic)
        print('  FAIL  no message (driver down, wrong IP, or another client holds the Hokuyo)')
        return False
    m = s.last
    span = s.stamps[-1] - s.stamps[0]
    hz = (len(s.stamps) - 1) / span if span > 0 else 0.0
    total = s.inf + s.nan + s.zero + s.finite
    pct = lambda n: 100.0 * n / total  # noqa: E731
    print('\n%s: %d msgs, %.1f Hz, frame_id %s' % (topic, len(s.stamps), hz, m.header.frame_id))
    print('  angles %.1f .. %.1f deg, %d beams, range_min %.3f, range_max %.1f m, '
          '%d intensities' % (math.degrees(m.angle_min), math.degrees(m.angle_max),
                              len(m.ranges), m.range_min, m.range_max, len(m.intensities)))
    print('  beams over window: +inf %.1f%%  NaN %.1f%%  zero %.1f%%  finite %.1f%% '
          '(%.3f .. %.2f m), %d finite beyond limits' % (
              pct(s.inf), pct(s.nan), pct(s.zero), pct(s.finite),
              s.min_r if s.finite else 0.0, s.max_r, s.out_of_range))
    checks = [
        ('rate 35..45 Hz', 35.0 <= hz <= 45.0, '%.1f Hz' % hz),
        ('frame_id', m.header.frame_id.endswith(FRAME.get(topic, '')), m.header.frame_id),
        ('intensities', len(m.intensities) == len(m.ranges), '%d' % len(m.intensities)),
    ]
    if expect_inf:
        checks += [
            ('no NaN (inf mode)', s.nan == 0, '%d NaN' % s.nan),
            ('finite within limits', s.out_of_range == 0, '%d outside' % s.out_of_range),
            ('no zero ranges', s.zero == 0, '%d zero' % s.zero),
        ]
    else:
        checks.append(('no +inf (upstream mode)', s.inf == 0, '%d inf' % s.inf))
    ok_all = True
    for name, ok, detail in checks:
        print('  %-5s %-22s %s' % ('PASS' if ok else 'FAIL', name, detail))
        ok_all &= ok
    if expect_inf and s.inf == 0:
        print('  NOTE  no +inf beam seen: point the lidar at open space '
              '(> 30 m or a window) to see no-return beams')
    return ok_all


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('topics', nargs='*')
    ap.add_argument('--secs', type=float, default=10.0)
    ap.add_argument('--expect-inf', default='auto')
    a = ap.parse_args()
    sides = os.environ.get('HOKUYOS', 'front,rear').split(',')
    topics = a.topics or [TOPIC[s.strip()] for s in sides if s.strip() in TOPIC]
    if a.expect_inf == 'auto':
        expect_inf = _true(os.environ.get('NO_RANGE_AS_INF', 'true'))
    else:
        expect_inf = _true(a.expect_inf)

    rclpy.init()
    node = rclpy.create_node('urg_scan_check')
    stats = {t: Stats() for t in topics}
    for t in topics:
        node.create_subscription(LaserScan, t, stats[t].add, qos_profile_sensor_data)
    end = time.monotonic() + a.secs
    while time.monotonic() < end:
        rclpy.spin_once(node, timeout_sec=0.05)

    print('expect no_range_as_inf=%s, %.0f s window' % (expect_inf, a.secs))
    results = [_report(t, stats[t], expect_inf) for t in topics]
    failed = not all(results)
    print('\nRESULT %s' % ('FAIL' if failed else 'PASS'))
    node.destroy_node()
    rclpy.shutdown()
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
