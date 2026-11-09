#!/bin/bash
# Host helper for the urg_node hardware test image (plain docker; robots have Docker 20.10 without compose).
# Get it from the image:  docker run --rm rr-urg-node-test:latest run.sh > run.sh && chmod +x run.sh
#
#   ./run.sh preflight      Hokuyos reachable, port 10940 free (ROS 1 driver stopped), Docker/seccomp
#   ./run.sh up             start the driver(s) (detached, restart unless-stopped)
#   ./run.sh check [secs]   rate, frame_id, intensities, +inf/NaN encoding; PASS/FAIL (default 10 s)
#   ./run.sh ab [secs]      check with NO_RANGE_AS_INF=true, then false (upstream), then restore true
#   ./run.sh hz             rate of the scan topics
#   ./run.sh status | logs | down | version
#
# Settings (env or .env next to this script):
#   HOKUYOS=front,rear  NO_RANGE_AS_INF=true  FRONT_IP=10.0.0.10  REAR_IP=10.0.1.10
#   MOUNTS=gen3/v1 (gen3/v1_xl, gen2/v4)  TF_PREFIX=  PUBLISH_TF=true
#   ROS_DOMAIN_ID (default 0)  ROS_AUTOMATIC_DISCOVERY_RANGE  ROS_STATIC_PEERS  IMAGE  NAME
set -eo pipefail
cd "$(dirname "$0")"
if [[ -f .env ]]; then set -a; source <(grep -vE '^\s*(#|$)' .env | sed 's/\s*#.*$//'); set +a; fi

IMAGE=${IMAGE:-urg-node-hw-test:latest}
NAME=${NAME:-urg_node_hw_test}
HOKUYOS=${HOKUYOS:-front,rear}
FRONT_IP=${FRONT_IP:-10.0.0.10}
REAR_IP=${REAR_IP:-10.0.1.10}
ENV_VARS="HOKUYOS NO_RANGE_AS_INF FRONT_IP REAR_IP MOUNTS TF_PREFIX PUBLISH_TF ROS_DOMAIN_ID
          ROS_AUTOMATIC_DISCOVERY_RANGE ROS_STATIC_PEERS FASTDDS_BUILTIN_TRANSPORTS HEALTH_TIMEOUT"

ips() {
    [[ ",$HOKUYOS," == *,front,* ]] && echo "front $FRONT_IP"
    [[ ",$HOKUYOS," == *,rear,* ]] && echo "rear $REAR_IP"
    return 0
}

# Docker < 20.10.10 rejects clone3 with EPERM, so glibc in Ubuntu 26.04 cannot start threads or processes.
# Use Docker's 20.10.10 default profile with clone3 allowed.
seccomp_file() {
    [[ -f seccomp-clone3.json ]] || docker run --rm --entrypoint cat "$IMAGE" /opt/urg_hw/seccomp-clone3.json > seccomp-clone3.json
    echo "$PWD/seccomp-clone3.json"
}
docker_args() {
    local v; v=$(docker version --format '{{.Server.Version}}' 2>/dev/null | cut -d- -f1)
    if [[ -n "$v" && "$(printf '%s\n20.10.10\n' "$v" | sort -V | head -1)" != "20.10.10" ]]; then
        echo "--security-opt seccomp=$(seccomp_file)"
    fi
}
env_args() {
    local v; for v in $ENV_VARS; do [[ -n "${!v}" ]] && printf -- '-e %s=%s ' "$v" "${!v}"; done; return 0
}
exec_ros() { docker exec "$NAME" /entrypoint.sh "$@"; }

preflight() {
    local ok=1 side ip
    echo "Docker server $(docker version --format '{{.Server.Version}}')$( [[ -n "$(docker_args)" ]] && echo ' (< 20.10.10: seccomp-clone3.json will be used)')"
    docker image inspect "$IMAGE" >/dev/null 2>&1 && echo "PASS  image $IMAGE present" || { echo "FAIL  image $IMAGE not loaded"; ok=0; }
    while read -r side ip; do
        if ping -c1 -W1 "$ip" >/dev/null 2>&1; then echo "PASS  $side Hokuyo $ip answers ping"
        else echo "FAIL  $side Hokuyo $ip does not answer ping (cable, power, or host route)"; ok=0; fi
        if (ss -tn 2>/dev/null || true) | grep -q "$ip:10940"; then
            echo "FAIL  $side Hokuyo $ip:10940 already has a TCP client (ROS 1 urg_node?). Stop the ROS 1 deployment."; ok=0
        else echo "PASS  $side Hokuyo $ip:10940 has no other client"; fi
    done < <(ips)
    [[ $ok == 1 ]] && echo "preflight PASS" || { echo "preflight FAIL"; return 1; }
}

up() {
    if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then echo "$NAME exists. Run ./run.sh down first."; exit 1; fi
    echo "Starting $NAME: hokuyos=$HOKUYOS no_range_as_inf=${NO_RANGE_AS_INF:-true} image $IMAGE"
    # shellcheck disable=SC2046
    docker run -d --name "$NAME" --network host --restart unless-stopped $(docker_args) \
        --log-opt max-size=10m --log-opt max-file=3 $(env_args) "$IMAGE" >/dev/null
    sleep 4; docker logs "$NAME" 2>&1 | grep -E "urg_node test:|Connected to|rror" | head -5 || true
}
down() { docker rm -f "$NAME" >/dev/null 2>&1 && echo "removed $NAME" || echo "$NAME not running"; }

check() {   # secs, expect-inf
    docker ps --format '{{.Names}}' | grep -qx "$NAME" || { echo "$NAME is not running: ./run.sh up"; exit 1; }
    exec_ros check --secs "${1:-10}" --expect-inf "${2:-auto}"
}

ab() {
    local secs=${1:-10} rc=0
    echo "=== A: NO_RANGE_AS_INF=true (Rapyuta, ROS 1 parity)"
    down >/dev/null; NO_RANGE_AS_INF=true up >/dev/null; sleep 6; check "$secs" true || rc=1
    echo; echo "=== B: NO_RANGE_AS_INF=false (upstream behaviour)"
    down >/dev/null; NO_RANGE_AS_INF=false up >/dev/null; sleep 6; check "$secs" false || rc=1
    echo; echo "=== restore NO_RANGE_AS_INF=${NO_RANGE_AS_INF:-true}"
    down >/dev/null; up >/dev/null
    echo; [[ $rc == 0 ]] && echo "A/B PASS" || echo "A/B FAIL"; return $rc
}

case "${1:-}" in
    preflight) preflight ;;
    up)        up ;;
    down)      down ;;
    check)     check "${2:-10}" ;;
    ab)        ab "${2:-10}" ;;
    hz)        for t in $(ips | awk '{print "raw_scan_" $1}'); do
                   printf '%-16s ' "$t"
                   exec_ros timeout 8 ros2 topic hz "/$t" --qos-reliability best_effort 2>/dev/null \
                       | awk '/average rate/{r=$3} END{print (r ? r " Hz" : "NO DATA")}' || true
               done ;;
    status)    docker ps -a --filter "name=^${NAME}$" --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
               docker inspect "$NAME" --format '{{range .State.Health.Log}}{{.End}} {{.Output}}{{end}}' 2>/dev/null | tail -3 ;;
    logs)      docker logs -f --tail 100 "$NAME" ;;
    version)   docker run --rm "$IMAGE" version ;;
    *)         sed -n '2,15p' "$0"; exit 1 ;;
esac
