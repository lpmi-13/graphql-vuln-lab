#!/usr/bin/env bash
# Publish / refresh the lab. Three independent pieces:
#   1. the rootfs OCI image              (docker build + push)
#   2. the custom playground             (labctl playground update)
#   3. the challenge content (index.md)  (labctl content push)
#
# The challenge references the playground by NAME (a kind: challenge cannot
# carry a custom drive inline), and the playground references the rootfs image
# by its oci:// URL. Keep the three names/tags below in sync with index.md and
# manifest.yaml.
#
#   ROOTFS_IMAGE     default: ghcr.io/lpmi-13/graphql-vuln-lab-rootfs:v2
#   PLAYGROUND_NAME  default: graphql-vuln-lab-6ac4f832
#   CHALLENGE_NAME   default: graphql-vuln-lab-ca696b14
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
rootfs_image="${ROOTFS_IMAGE:-ghcr.io/lpmi-13/graphql-vuln-lab-rootfs:v2}"
playground_name="${PLAYGROUND_NAME:-graphql-vuln-lab-6ac4f832}"
challenge_name="${CHALLENGE_NAME:-graphql-vuln-lab-ca696b14}"

command -v labctl >/dev/null || { echo "labctl is required" >&2; exit 1; }
labctl auth whoami >/dev/null 2>&1 || { echo "run: labctl auth login" >&2; exit 1; }

echo "== 1/3 build + push rootfs image =="
# Needs a ghcr token with write:packages scope:
#   docker login ghcr.io -u <user>   # paste a PAT with write:packages
ROOTFS_IMAGE="${rootfs_image}" PUSH_IMAGE=1 \
  bash "${repo_root}/playground/iximiuz/build-rootfs-image.sh"

echo "== 2/3 update custom playground =="
labctl playground update "${playground_name}" -f "${repo_root}/playground/iximiuz/manifest.yaml"

echo "== 3/3 push challenge content (index.md only) =="
stage="$(mktemp -d)"; trap 'rm -rf "${stage}"' EXIT
cp "${repo_root}/index.md" "${stage}/index.md"
[ -d "${repo_root}/__static__" ] && cp -a "${repo_root}/__static__" "${stage}/__static__"
labctl content push challenge "${challenge_name}" --dir "${stage}" --force

echo "Done:"
echo "  playground: https://labs.iximiuz.com/playgrounds/${playground_name}"
echo "  challenge:  https://labs.iximiuz.com/challenges/${challenge_name}"
