#!/bin/bash
# Build the urg_node hardware test image from this checkout. The 'test' stage (package tests) runs first;
# the image is built only if it passes.
#   test/hardware/build.sh            image urg-node-hw-test:<date>-<sha> + urg_node_hw_test_<tag>.tar.gz
#   SAVE=0 test/hardware/build.sh     image only (no tarball)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
SHA=$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- . || echo -dirty)
TAG=${TAG:-$(date +%Y%m%d)-$SHA}
NAME=${IMAGE_NAME:-urg-node-hw-test}
IMG=$NAME:$TAG
OUT=${OUT_DIR:-$ROOT/test/hardware}
echo ">>> test stage ($SHA)"
docker build -f test/hardware/Dockerfile --target test -t "$NAME:test-$TAG" . 2>&1 | tail -45
echo ">>> runtime image $IMG"
docker build -f test/hardware/Dockerfile --build-arg GIT_SHA="$(git rev-parse HEAD)" --build-arg VERSION="$TAG" \
    --build-arg IMAGE_REF="$IMG" -t "$IMG" -t "$NAME:latest" .
docker image ls "$IMG" --format 'image {{.Repository}}:{{.Tag}} {{.Size}}'
if [[ "${SAVE:-1}" == "1" ]]; then
    docker save "$IMG" "$NAME:latest" | gzip -1 > "$OUT/urg_node_hw_test_${TAG}.tar.gz"
    ls -lh "$OUT/urg_node_hw_test_${TAG}.tar.gz"
fi
