FROM quay.io/ceph/ceph:v20

RUN dnf install -y jq && dnf clean all

COPY ceph.conf /etc/ceph/ceph.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
