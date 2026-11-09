# Hardware test image for this urg_node (ROS 2 lyrical): builds the checked-out source, runs its tests,
# and packs the Hokuyo test launch, scan checks and the host helper (README.md).
# Build from the repository root: test/hardware/build.sh

ARG ROS_DISTRO=lyrical

############################ builder ############################
FROM ros:${ROS_DISTRO}-ros-base AS builder
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Whole checkout (test/hardware/Dockerfile.dockerignore drops .git and image tarballs)
COPY . /ws/src/urg_node

RUN apt-get update && (rosdep init 2>/dev/null || true) && rosdep update -q --rosdistro ${ROS_DISTRO} \
    && rosdep install -y -q --from-paths /ws/src --ignore-src --rosdistro ${ROS_DISTRO} \
    && rm -rf /var/lib/apt/lists/*

RUN cd /ws && source /opt/ros/${ROS_DISTRO}/setup.bash \
    && colcon build --merge-install --install-base /opt/urg --event-handlers console_direct- \
         --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON \
    && rm -rf /opt/urg/include /opt/urg/share/*/cmake

############################ test ############################
# The package tests (gtest incl. test_no_return_as_inf, ament linters). The build fails if a test fails.
FROM builder AS test
RUN cd /ws && source /opt/ros/${ROS_DISTRO}/setup.bash \
    && colcon test --merge-install --install-base /opt/urg --packages-select urg_node \
         --event-handlers console_direct- --return-code-on-test-failure \
    ; rc=$?; colcon test-result --test-result-base build --verbose | tail -40; exit $rc

############################ runtime ############################
FROM ros:${ROS_DISTRO}-ros-core AS runtime
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Runtime dependencies of urg_node missing in ros-core
RUN apt-get update && apt-get install -y --no-install-recommends \
        ros-${ROS_DISTRO}-urg-c \
        ros-${ROS_DISTRO}-urg-node-msgs \
        ros-${ROS_DISTRO}-laser-proc \
        ros-${ROS_DISTRO}-diagnostic-updater \
        ros-${ROS_DISTRO}-tf2-ros \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/urg /opt/urg
COPY --chmod=755 test/hardware/entrypoint.sh /entrypoint.sh
COPY test/hardware/hokuyo.launch.py test/hardware/scan_check.py test/hardware/scan_health.py \
     test/hardware/run.sh test/hardware/seccomp-clone3.json /opt/urg_hw/
COPY test/hardware/config /opt/urg_hw/config

ARG GIT_SHA=unknown
ARG VERSION=dev
ARG IMAGE_REF=urg-node-hw-test:latest
RUN printf 'image %s\nurg_node source %s\n' "${VERSION}" "${GIT_SHA}" > /opt/urg_hw/VERSION

# Shared memory between root containers fails without a shared /dev/shm: use UDP
ENV HOKUYOS=front,rear \
    NO_RANGE_AS_INF=true \
    MOUNTS=gen3/v1 \
    FASTDDS_BUILTIN_TRANSPORTS=UDPv4 \
    IMAGE_REF=${IMAGE_REF}

LABEL org.opencontainers.image.title="urg-node-hw-test" \
      org.opencontainers.image.description="Hokuyo hardware test image for rapyuta-robotics/urg_node (ROS 2 lyrical)" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}"

HEALTHCHECK --interval=30s --timeout=15s --start-period=30s --retries=3 CMD ["/entrypoint.sh", "health"]
ENTRYPOINT ["/entrypoint.sh"]
CMD ["launch"]
