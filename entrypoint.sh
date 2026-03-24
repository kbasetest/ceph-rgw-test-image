#!/bin/bash
set -e

RGW_PORT="${RGW_PORT:-8080}"
RGW_ACCESS_KEY="${RGW_ACCESS_KEY:-testaccesskey}"
RGW_SECRET_KEY="${RGW_SECRET_KEY:-testsecretkey}"

mkdir -p /var/lib/ceph/rgw

# Start radosgw in the background
radosgw \
  --name client.rgw.test \
  --no-mon-config \
  --rgw-frontends="beast port=${RGW_PORT}" &

RGW_PID=$!

echo "Waiting for RGW to be ready..."
timeout 30 bash -c "until curl -sf http://127.0.0.1:${RGW_PORT} > /dev/null 2>&1; do sleep 1; done"

# Get or create the account and capture the account ID
if ACCOUNT_JSON=$(radosgw-admin account get --no-mon-config --account-name="testaccount" 2>/dev/null); then
  echo "Account already exists, skipping creation"
else
  ACCOUNT_JSON=$(radosgw-admin account create --no-mon-config --account-name="testaccount")
fi

ACCOUNT_ID=$(echo "${ACCOUNT_JSON}" | jq -r '.id')

# Create the account root user if it doesn't already exist
# --account-root grants full IAM permissions within the account
if radosgw-admin user info --no-mon-config --uid="root" &>/dev/null; then
  echo "User already exists, skipping creation"
else
  radosgw-admin user create \
    --no-mon-config \
    --uid="root" \
    --display-name="Account Root" \
    --account-id="${ACCOUNT_ID}" \
    --account-root \
    --access-key="${RGW_ACCESS_KEY}" \
    --secret="${RGW_SECRET_KEY}"
fi

echo ""
echo "========================================="
echo " RGW ready"
echo "========================================="
echo " S3 endpoint : http://127.0.0.1:${RGW_PORT}"
echo " Access key  : ${RGW_ACCESS_KEY}"
echo " Secret key  : ${RGW_SECRET_KEY}"
echo "========================================="

# Hand off to radosgw as PID 1
wait $RGW_PID
