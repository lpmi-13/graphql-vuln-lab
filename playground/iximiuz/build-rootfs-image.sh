#!/usr/bin/env bash
# Build the custom rootfs OCI image for the GraphQL security lab.
#
#   ROOTFS_IMAGE   full image ref (default: ghcr.io/lpmi-13/graphql-vuln-lab-rootfs:v2)
#   PUSH_IMAGE     set to 1 to docker push after building
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

rootfs_image="${ROOTFS_IMAGE:-ghcr.io/lpmi-13/graphql-vuln-lab-rootfs:v2}"
push_image="${PUSH_IMAGE:-0}"

echo "Building ${rootfs_image} ..."
docker build \
  -f playground/iximiuz/Dockerfile \
  -t "${rootfs_image}" \
  "${repo_root}"

if [[ "${push_image}" != "0" ]]; then
  echo "Pushing ${rootfs_image} ..."
  docker push "${rootfs_image}"
fi

echo "Done: ${rootfs_image}"
