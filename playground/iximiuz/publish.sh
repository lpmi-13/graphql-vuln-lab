#!/usr/bin/env bash
# Publish / refresh the lab. Three pieces:
#   1. the rootfs OCI image              (docker build + push)
#   2. the custom playground             (labctl playground update)
#   3. the challenge content (index.md)  (labctl content push)
#
# The challenge references the playground by NAME (a kind: challenge cannot
# carry a custom drive inline), and the playground references the rootfs image
# by its oci:// URL. Read that image from manifest.yaml, increment its vN tag,
# and record the new tag there only after the image push and playground update.
#
#   PLAYGROUND_NAME  default: graphql-vuln-lab-6ac4f832
#   CHALLENGE_NAME   default: graphql-vuln-lab-ca696b14
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
manifest="${repo_root}/playground/iximiuz/manifest.yaml"
playground_name="${PLAYGROUND_NAME:-graphql-vuln-lab-6ac4f832}"
challenge_name="${CHALLENGE_NAME:-graphql-vuln-lab-ca696b14}"

die() { echo "$*" >&2; exit 1; }

# Match the OCI drive source, preserving its indentation when writing the next
# manifest. Require exactly one so a new drive cannot silently select the wrong
# image.
source_re='^([[:space:]]*-[[:space:]]*source:[[:space:]]*oci://)([^[:space:]]+)([[:space:]]*)$'
images=()
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ $source_re ]]; then
    images+=("${BASH_REMATCH[2]}")
  fi
done < "$manifest"
[[ ${#images[@]} -eq 1 ]] || die "Expected one OCI drive source in ${manifest}; found ${#images[@]}."

current_image="${images[0]}"
if [[ "$current_image" =~ ^(ghcr\.io/[^:[:space:]]+):v([1-9][0-9]*)$ ]]; then
  image_repo="${BASH_REMATCH[1]}"
  current_version="${BASH_REMATCH[2]}"
else
  die "Expected a ghcr.io rootfs image tagged vN in ${manifest}; found ${current_image}."
fi
next_version=$((10#${current_version} + 1))
next_image="${image_repo}:v${next_version}"
echo "Rootfs image: ${current_image} -> ${next_image}"

# Prepare the next manifest before publishing, but keep the current version on
# disk if the build, push, or playground update fails.
next_manifest="$(mktemp --suffix=.yaml "${manifest}.next.XXXXXX")"
stage=""
cleanup() {
  rm -f "$next_manifest"
  if [[ -n "$stage" ]]; then rm -rf "$stage"; fi
}
trap cleanup EXIT

replacements=0
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ $source_re ]]; then
    [[ "${BASH_REMATCH[2]}" == "$current_image" ]] || die "Manifest changed during publish."
    line="${BASH_REMATCH[1]}${next_image}${BASH_REMATCH[3]}"
    replacements=$((replacements + 1))
  fi
  printf '%s\n' "$line"
done < "$manifest" > "$next_manifest"
[[ $replacements -eq 1 ]] || die "Could not update the OCI drive source in ${manifest}."
chmod --reference="$manifest" "$next_manifest"

command -v labctl >/dev/null || { echo "labctl is required" >&2; exit 1; }
labctl auth whoami >/dev/null 2>&1 || { echo "run: labctl auth login" >&2; exit 1; }

echo "== 1/3 build + push rootfs image =="
# Needs a ghcr token with write:packages scope:
#   docker login ghcr.io -u <user>   # paste a PAT with write:packages
ROOTFS_IMAGE="${next_image}" PUSH_IMAGE=1 \
  bash "${repo_root}/playground/iximiuz/build-rootfs-image.sh"

echo "== 2/3 update custom playground =="
labctl playground update "${playground_name}" -f "$next_manifest"
mv "$next_manifest" "$manifest"

echo "== 3/3 push challenge content (index.md only) =="
stage="$(mktemp -d)"
cp "${repo_root}/index.md" "${stage}/index.md"
[ -d "${repo_root}/__static__" ] && cp -a "${repo_root}/__static__" "${stage}/__static__"
labctl content push challenge "${challenge_name}" --dir "${stage}" --force

echo "Done:"
echo "  image:      ${next_image}"
echo "  playground: https://labs.iximiuz.com/playgrounds/${playground_name}"
echo "  challenge:  https://labs.iximiuz.com/challenges/${challenge_name}"
