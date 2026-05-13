FROM quay.io/ceph/ceph:v20

RUN dnf install -y jq && dnf clean all

COPY ceph.conf /etc/ceph/ceph.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

HEALTHCHECK --interval=1s --timeout=3s --retries=60 \
  CMD curl -s http://127.0.0.1:${RGW_PORT:-8080}/ | grep -q '<'

ENTRYPOINT ["/entrypoint.sh"]
