#!/usr/bin/env bash
# Restart the GraphQL service so your edits to the project take effect.
set -euo pipefail
echo "Restarting graphql-lab.service ..."
sudo systemctl restart graphql-lab.service
/opt/graphql-lab-tasks/wait_ready.sh
