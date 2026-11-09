"""
Hardware test launch: PA-AMR Hokuyos with this urg_node (see README.md).

Starts one urg_node_driver per selected Hokuyo, with the ROS 1 PA-AMR settings
(rr_pa_amr_description/sensors/hokuyo.yaml). Topics raw_scan_front / raw_scan_rear, as in ROS 1.
Every argument defaults to an environment variable, so the container is configured with -e.
"""

import math
import os

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, LogInfo, OpaqueFunction
from launch.substitutions import EnvironmentVariable, LaunchConfiguration
from launch_ros.actions import Node
import yaml

CONFIG_DIR = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'config')

ARGS = [
    # name, environment variable, default, description
    ('hokuyos', 'HOKUYOS', 'front,rear', 'Comma list: front, rear, or front,rear'),
    ('no_range_as_inf', 'NO_RANGE_AS_INF', 'true',
     'true = no-return beams are +inf (ROS 1 parity); false = upstream behaviour'),
    ('front_ip', 'FRONT_IP', '10.0.0.10', 'Front Hokuyo IP address'),
    ('rear_ip', 'REAR_IP', '10.0.1.10', 'Rear Hokuyo IP address'),
    ('mounts', 'MOUNTS', 'gen3/v1', 'Mount poses for TF: gen3/v1, gen3/v1_xl or gen2/v4'),
    ('tf_prefix', 'TF_PREFIX', '', 'Frame prefix, for example amr03/'),
    ('publish_tf', 'PUBLISH_TF', 'true', 'Publish base_link -> scan_*_link'),
]

SIDES = {
    'front': ('hokuyo_front', 'scan_front_link', 'raw_scan_front', 'front_ip'),
    'rear': ('hokuyo_rear', 'scan_rear_link', 'raw_scan_rear', 'rear_ip'),
}


def _true(value):
    return str(value).strip().lower() in ('1', 'true', 'yes', 'on')


def _setup(context):
    get = lambda name: LaunchConfiguration(name).perform(context)  # noqa: E731
    sides = [s.strip().lower() for s in get('hokuyos').split(',') if s.strip()]
    bad = [s for s in sides if s not in SIDES]
    if bad or not sides:
        raise RuntimeError("HOKUYOS must be front, rear or front,rear, got '%s'" % get('hokuyos'))
    prefix = get('tf_prefix')
    inf = _true(get('no_range_as_inf'))
    cfg = lambda name: os.path.join(CONFIG_DIR, name)  # noqa: E731

    summary = 'urg_node test: hokuyos=%s no_range_as_inf=%s mounts=%s tf_prefix="%s"' % (
        ','.join(sides), inf, get('mounts'), prefix)
    actions = [LogInfo(msg=summary)]
    for side in sides:
        name, frame, topic, ip_arg = SIDES[side]
        actions.append(Node(
            package='urg_node', executable='urg_node_driver', name=name, output='screen',
            respawn=True, respawn_delay=2.0,
            parameters=[cfg('hokuyo.yaml'), {'laser_frame_id': prefix + frame,
                                             'ip_address': get(ip_arg),
                                             'no_range_as_inf': inf}],
            remappings=[('scan', topic)],
        ))

    if _true(get('publish_tf')):
        with open(cfg('mounts.yaml')) as f:
            all_mounts = yaml.safe_load(f)
        if get('mounts') not in all_mounts:
            raise RuntimeError("MOUNTS must be one of %s, got '%s'" % (
                ', '.join(all_mounts), get('mounts')))
        for side in sides:
            frame = SIDES[side][1]
            p = all_mounts[get('mounts')][frame]
            actions.append(Node(
                package='tf2_ros', executable='static_transform_publisher', name='tf_' + frame,
                output='log',
                arguments=['--x', str(p['x']), '--y', str(p['y']), '--z', str(p['z']),
                           '--roll', str(math.radians(p['roll'])),
                           '--pitch', str(math.radians(p['pitch'])),
                           '--yaw', str(math.radians(p['yaw'])),
                           '--frame-id', prefix + 'base_link', '--child-frame-id', prefix + frame],
            ))
    return actions


def generate_launch_description():
    return LaunchDescription(
        [DeclareLaunchArgument(name, default_value=EnvironmentVariable(env, default_value=default),
                               description='%s (env %s, default "%s")' % (desc, env, default))
         for name, env, default, desc in ARGS]
        + [OpaqueFunction(function=_setup)])
