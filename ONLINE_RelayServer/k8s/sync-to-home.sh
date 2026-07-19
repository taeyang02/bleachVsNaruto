#!/usr/bin/env bash
# Sync manifests to server layout: ~/k8s/manifests/base/bvn-online-relay/
# Usage (on server, from this repo or after copy):
#   ./k8s/sync-to-home.sh
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/manifests/base/bvn-online-relay" && pwd)"
DST_DIR="${HOME}/k8s/manifests/base/bvn-online-relay"

mkdir -p "${DST_DIR}"
cp -v "${SRC_DIR}/"*.yaml "${DST_DIR}/"
echo "[OK] synced -> ${DST_DIR}"
echo "Apply: kubectl apply -k ${DST_DIR}"
