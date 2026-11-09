# Hardware test (Hokuyo on a PA-AMR)

A test image that runs this urg_node against real Hokuyos and checks the scans. Nothing in this directory is
built or installed by colcon.

| File | What it does |
|---|---|
| `Dockerfile`, `build.sh` | Build the checked-out source on ROS 2 lyrical, run the package tests (`test` stage), then build a small runtime image. The image is made only if the tests pass. |
| `hokuyo.launch.py`, `config/` | One `urg_node_driver` per Hokuyo with the PA-AMR settings (from ROS 1 `rr_pa_amr_description/sensors/hokuyo.yaml`), topics `raw_scan_front` / `raw_scan_rear`, static TF `base_link` -> `scan_*_link` |
| `scan_check.py` | PASS/FAIL check of rate, `frame_id`, intensities and the no-return encoding (+inf, NaN, 0) |
| `run.sh` | Host helper on the robot: `preflight`, `up`, `check`, `ab`, `hz`, `status`, `logs`, `down` |
| `viz/` | On a laptop: `view_rviz.sh` (RViz, fixed frame `base_link`) and `stream_check.sh` (rate and bandwidth over the network) |
| `seccomp-clone3.json` | Docker 20.10.10 default seccomp profile with `clone3` allowed, for robots with Docker < 20.10.10 |

## Build

```bash
test/hardware/build.sh          # image urg-node-hw-test:<date>-<sha> + test/hardware/urg_node_hw_test_<tag>.tar.gz
```

## Run on the robot

Stop the ROS 1 lidar drivers first: each Hokuyo accepts one TCP client.

```bash
docker load -i urg_node_hw_test_<tag>.tar.gz
docker run --rm urg-node-hw-test:latest run.sh > run.sh && chmod +x run.sh
./run.sh preflight      # Hokuyos answer ping, port 10940 free, Docker version
./run.sh up             # both Hokuyos, no_range_as_inf=true
./run.sh check 20       # PASS/FAIL over 20 s
./run.sh ab 15          # check with no_range_as_inf=true, then false, then restore true
```

Point the lidars at open space (> 30 m, a window or a door), else there are no no-return beams to check.

| Variable | Default | Meaning |
|---|---|---|
| `HOKUYOS` | `front,rear` | which drivers start |
| `NO_RANGE_AS_INF` | `true` | `true` = no-return beams are +inf (ROS 1 PA-AMR behaviour) |
| `FRONT_IP`, `REAR_IP` | `10.0.0.10`, `10.0.1.10` | Hokuyo addresses |
| `MOUNTS` | `gen3/v1` | TF poses: `gen3/v1`, `gen3/v1_xl`, `gen2/v4` |
| `TF_PREFIX`, `PUBLISH_TF` | empty, `true` | frames |
| `ROS_DOMAIN_ID`, `ROS_AUTOMATIC_DISCOVERY_RANGE`, `ROS_STATIC_PEERS` | ROS defaults | DDS; put them in `.env` next to `run.sh` |

**Docker older than 20.10.10** blocks `clone3`, so Ubuntu 26.04 programs cannot start threads. `run.sh` then
adds `--security-opt seccomp=seccomp-clone3.json`. Do not use `--privileged` instead.

## Stream to RViz on a laptop

On the robot, write `.env` next to `run.sh` and restart:

```bash
printf 'ROS_DOMAIN_ID=78\nROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET\nROS_STATIC_PEERS=<laptop-ip>\n' > .env
./run.sh down && ./run.sh up
```

On the laptop (ROS 2 lyrical installed):

```bash
test/hardware/viz/stream_check.sh <robot-ip> 78     # rate and bandwidth of both scans
test/hardware/viz/view_rviz.sh <robot-ip> 78        # RViz, scans colored by intensity
```

The image uses `FASTDDS_BUILTIN_TRANSPORTS=UDPv4`. With `ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST`, a second
container on the robot sees the topics but receives no data; `run.sh check` and `hz` run inside the driver
container and are not affected.

## Results

2026-11-09, amr03 (PA-AMR gen3 v1, Docker 20.10.7), source 88b4f29:

| | Front (B2111955) | Rear (B2106258) |
|---|---|---|
| Rate | 39.9 Hz | 39.9 Hz |
| Angles, beams, range_max | ±90°, 721, 30 m | ±135°, 1081, 15 m |
| `no_range_as_inf=true` | 19 % +inf, 0 NaN, 0 zero: PASS | 46 % +inf, 0 NaN, 0 zero: PASS |
| `no_range_as_inf=false` | no-return beams published as finite 65.53 m | same |
| To a laptop over Wi-Fi (domain 78) | 39.95 Hz, 233 KB/s | 39.94 Hz, 349 KB/s |

With `no_range_as_inf=false` (upstream behaviour) the Hokuyo no-return code 65533 mm is published as a finite
65.53 m range, beyond `range_max`. A costmap reads it as an obstacle and does not clear.
