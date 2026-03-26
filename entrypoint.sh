#!/bin/bash
set -e

RGW_PORT="${RGW_PORT:-8080}"
RGW_ACCESS_KEY="${RGW_ACCESS_KEY:-testaccesskey}"
RGW_SECRET_KEY="${RGW_SECRET_KEY:-testsecretkey}"

# Always start fresh — memstore is in-memory so there is nothing to recover
rm -rf /var/lib/ceph/mon/ceph-a /var/lib/ceph/mgr/ceph-a /var/lib/ceph/osd/ceph-0
mkdir -p /var/lib/ceph/mon/ceph-a /var/lib/ceph/mgr/ceph-a /var/lib/ceph/osd/ceph-0 /var/log/ceph

# Generate a cluster FSID and stamp it into ceph.conf so all daemons agree
# without needing to negotiate it via the MON at bootstrap time
FSID=$(uuidgen)
sed -i "s/\[global\]/[global]\n    fsid = $FSID/" /etc/ceph/ceph.conf

# Build a monmap — a binary description of the monitor topology (name + address).
# The MON needs this before it can initialise its on-disk state.
monmaptool --create --add a 127.0.0.1 --fsid "$FSID" /tmp/monmap 2>/dev/null
# Initialise the MON's data directory (one-shot, like mkfs on a filesystem).
ceph-mon --id a --mkfs --monmap /tmp/monmap
# Start the MON daemon; everything else registers through it.
ceph-mon --id a &

echo "Waiting for MON..."
timeout 30 bash -c "until ceph -s &>/dev/null; do sleep 1; done"

# Start MGR
ceph-mgr --id a &

echo "Waiting for MGR..."
timeout 60 bash -c "until ceph mgr stat 2>/dev/null | grep -q 'active_name'; do sleep 1; done"

# Bootstrap and start OSD (memstore: in-memory, no block device or privileges needed)
# Initialise the OSD's data directory (one-shot).
ceph-osd --id 0 --osd-objectstore memstore --mkfs
# Ask the MON to allocate an OSD slot; it assigns the ID (always 0 on a fresh cluster).
ceph osd create
# Start the OSD daemon.
ceph-osd --id 0 --osd-objectstore memstore &

echo "Waiting for OSD..."
timeout 30 bash -c "until ceph osd stat 2>/dev/null | grep -q '1 up'; do sleep 1; done"

# Enable the dashboard (MGR module). Disable SSL and set the port, then create an admin user.
# --force-password bypasses the password strength check (fine for a test image).
ceph mgr module enable dashboard
ceph config set mgr mgr/dashboard/ssl false
ceph config set mgr mgr/dashboard/server_port 8443
echo -n "admin" | ceph dashboard ac-user-create admin administrator -i - --force-password

# Start RGW
radosgw -f --name client.rgw.test --rgw-frontends="beast port=${RGW_PORT}" & # -f = foreground, prevents daemonization so wait $RGW_PID works
RGW_PID=$!

echo "Waiting for RGW..."
timeout 30 bash -c "until curl -sf http://127.0.0.1:${RGW_PORT} &>/dev/null; do sleep 1; done"

# Create account and root user
ACCOUNT_JSON=$(radosgw-admin account create --account-name="testaccount")
ACCOUNT_ID=$(echo "${ACCOUNT_JSON}" | jq -r '.id')

radosgw-admin user create \
  --uid="root" \
  --display-name="AccountRoot" \
  --account-id="${ACCOUNT_ID}" \
  --account-root \
  --access-key="${RGW_ACCESS_KEY}" \
  --secret="${RGW_SECRET_KEY}"

echo ""
echo "========================================="
echo " RGW ready"
echo "========================================="
echo " S3 endpoint : http://127.0.0.1:${RGW_PORT}"
echo " Access key  : ${RGW_ACCESS_KEY}"
echo " Secret key  : ${RGW_SECRET_KEY}"
echo " Dashboard   : http://127.0.0.1:8443  (admin / admin)"
echo "========================================="

# Keep the container alive until RGW exits.
wait $RGW_PID
