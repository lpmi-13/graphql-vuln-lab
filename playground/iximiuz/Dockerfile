# syntax=docker/dockerfile:1
#
# Custom rootfs for the GraphQL security lab. Bakes the Django + Strawberry
# project (stock / vulnerable at its defaults), a Python venv with pinned deps,
# the grader scripts, and a probe toolbox, served by uvicorn under systemd.
#
# Build context is the repository root (see build-rootfs-image.sh).
FROM ghcr.io/iximiuz/labs/rootfs:ubuntu-24-04

USER root
ENV HOME=/root

COPY app /opt/graphql-lab
COPY tasks /opt/graphql-lab-tasks
COPY toolbox /opt/graphql-lab-toolbox
COPY playground/iximiuz/image/graphql-lab.service /etc/systemd/system/graphql-lab.service
COPY playground/iximiuz/image/graphql-lab.sudoers /opt/iximiuz-labs/graphql-lab.sudoers

RUN set -eu; \
  apt-get update; \
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    httpie \
    jq \
    python3 \
    python3-venv \
    sudo; \
  rm -rf /var/lib/apt/lists/*; \
  \
  python3 -m venv /opt/graphql-lab-venv; \
  /opt/graphql-lab-venv/bin/pip install --no-cache-dir --upgrade pip; \
  /opt/graphql-lab-venv/bin/pip install --no-cache-dir -r /opt/graphql-lab/requirements.txt; \
  \
  # Bake a migrated + seeded database into the pristine project.
  rm -f /opt/graphql-lab/db.sqlite3; \
  ( cd /opt/graphql-lab \
    && /opt/graphql-lab-venv/bin/python manage.py migrate --noinput \
    && /opt/graphql-lab-venv/bin/python manage.py seed_data ); \
  find /opt/graphql-lab -name '__pycache__' -type d -prune -exec rm -rf {} +; \
  \
  # Keep a pristine copy for reset.sh.
  cp -a /opt/graphql-lab /opt/graphql-lab-pristine; \
  \
  chmod 0755 /opt/graphql-lab-toolbox/*.sh /opt/graphql-lab-tasks/*.sh; \
  install -m 0440 /opt/iximiuz-labs/graphql-lab.sudoers /etc/sudoers.d/graphql-lab; \
  visudo -cf /etc/sudoers.d/graphql-lab; \
  \
  mkdir -p /etc/systemd/system/multi-user.target.wants; \
  ln -sf /etc/systemd/system/graphql-lab.service \
    /etc/systemd/system/multi-user.target.wants/graphql-lab.service; \
  \
  if id laborant >/dev/null 2>&1; then \
    chown -R laborant:laborant /opt/graphql-lab; \
    ln -sfn /opt/graphql-lab-toolbox /home/laborant/toolbox; \
    chown -h laborant:laborant /home/laborant/toolbox; \
    ln -sfn /opt/graphql-lab /home/laborant/graphql-lab; \
    chown -h laborant:laborant /home/laborant/graphql-lab; \
    grep -qxF 'cd ~/graphql-lab' /home/laborant/.bashrc || echo 'cd ~/graphql-lab' >> /home/laborant/.bashrc; \
  fi; \
  \
  command -v curl >/dev/null; \
  command -v jq >/dev/null; \
  command -v python3 >/dev/null; \
  command -v sudo >/dev/null; \
  test -x /opt/graphql-lab-venv/bin/uvicorn; \
  test -f /opt/graphql-lab/db.sqlite3; \
  test -f /opt/graphql-lab-pristine/db.sqlite3; \
  test -f /opt/graphql-lab/graphql_lab/schema.py; \
  test -x /opt/graphql-lab-tasks/patch_introspection.sh

USER laborant
ENV HOME=/home/laborant
