#!/usr/bin/env bash
# Restore the project to its pristine (default / vulnerable) state and restart.
# Run via: sudo /opt/graphql-lab-toolbox/reset.sh
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

project="/opt/graphql-lab"
pristine="/opt/graphql-lab-pristine"

echo "Restoring ${project} from ${pristine} ..."
rm -rf "${project}"
cp -a "${pristine}" "${project}"
if id laborant >/dev/null 2>&1; then
  chown -R laborant:laborant "${project}"
fi

systemctl restart graphql-lab.service
echo "Reset complete; service restarted."
