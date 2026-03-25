# ceph-rgw-test-image

A self-contained Ceph cluster in a single Docker container, intended for **development and testing only**. It provides a real Ceph RADOS Gateway with full IAM support (S3, IAM, STS APIs) and a dashboard, with no host dependencies beyond Docker.

## ⚠️ Not for production

This image makes several deliberate trade-offs for simplicity:

- All object data is stored in RAM and is **wiped every time the container restarts**
- Authentication between Ceph daemons is disabled
- Dashboard credentials are hardcoded (`admin` / `admin`)
- A single monitor, single OSD, and single RGW share one container

## Why a full Ceph cluster, not a lightweight stub?

The obvious approach for a test fixture is a lightweight standalone RGW using the `dbstore` backend, which runs without any monitor, OSD, or MGR. We tried this first, but `dbstore` does not implement the Ceph account API (`account create` returns `EOPNOTSUPP`). Since the account model is what enables the full IAM surface (user policies, roles, AssumeRole, etc.), `dbstore` was a dead end for our use case.

The next question was whether a real Ceph cluster requires `--privileged` to run in Docker. It does not, provided the OSD uses the `memstore` backend instead of `BlueStore`. `memstore` keeps all object data in RAM — no block devices, no loop devices, no elevated capabilities needed. This makes the image safe to use in GitHub Actions runners and on developer laptops without any special Docker configuration.

## Why is all data in memory?

`memstore` is an in-memory OSD backend intended for testing. It was chosen specifically because it avoids the need for block devices or `--privileged`. The trade-off is that all S3 objects, buckets, users, and IAM state are lost when the container stops. For a test fixture that starts fresh for each test run, this is the correct behaviour.

## Usage

### Standalone

```bash
docker run --rm \
  -p 8080:8080 \
  -p 8445:8443 \
  -e RGW_ACCESS_KEY=myaccesskey \
  -e RGW_SECRET_KEY=mysecretkey \
  ghcr.io/kbasetest/ceph-rgw-test-image:latest
```

> If you don't run Ceph locally you can use the standard `8443` port directly instead of mapping to `8445`.

The container prints a summary when ready:

```
=========================================
 RGW ready
=========================================
 S3 endpoint : http://127.0.0.1:8080
 Access key  : myaccesskey
 Secret key  : mysecretkey
 Dashboard   : http://127.0.0.1:8443  (admin / admin)
=========================================
```

### Docker Compose

Wait for the container to be healthy before running tests:

```bash
docker compose up --build --wait
```

### Connecting

The S3 endpoint speaks standard S3 (path-style). The root user is pre-created with the configured credentials and has full IAM permissions within the account.

Example with the AWS CLI, assuming you call your profile `cephtest`:

```bash
$ aws --profile cephtest configure set endpoint_url http://localhost:8080
$ aws --profile cephtest configure 
AWS Access Key ID [None]: testaccesskey
AWS Secret Access Key [None]: testsecretkey
Default region name [None]: default
Default output format [None]:
```

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RGW_PORT` | `8080` | Port RGW listens on inside the container |
| `RGW_ACCESS_KEY` | `testaccesskey` | S3 access key for the pre-created root user |
| `RGW_SECRET_KEY` | `testsecretkey` | S3 secret key for the pre-created root user |

## Dashboard

The Ceph dashboard is available at `http://localhost:8445` (when using the compose file above) with credentials `admin` / `admin`.

## Known issues

### RGW section of the dashboard does not work

The **Object Gateway** section of the dashboard (daemons, buckets, users) shows no data and reports RGW as not running, even though the S3 endpoint is fully functional.

In Ceph v20 (Tentacle), RGW no longer registers itself in the MON service map when running outside of cephadm. The dashboard discovers RGW daemons by reading the service map, so it cannot find RGW in a manually deployed cluster. This appears to be a deliberate design decision in Tentacle — the dashboard's RGW integration is built around cephadm as the deployment mechanism.

The S3, IAM, and STS APIs are unaffected.
