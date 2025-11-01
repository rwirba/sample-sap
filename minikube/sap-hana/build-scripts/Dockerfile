# -------------------------------------------------------------------
# SAP HANA Express (Full Edition) Wrapper Image
# Includes Cockpit & XS Advanced
# -------------------------------------------------------------------

ARG HXE_BASE_IMAGE=docker.io/saplabs/hanaexpress:2.00.082.00.20250528.1_full
FROM ${HXE_BASE_IMAGE}

LABEL org.opencontainers.image.title="SAP HANA Express Wrapper (Full Edition)" \
      org.opencontainers.image.description="Custom wrapper on top of SAP HANA Express Full Edition with Cockpit and XS Advanced support, built via Podman/Ansible automation." \
      maintainer="ryandevlab"

ENV HANA_LICENSE=accept \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TZ=UTC

# Create writable mount directory
RUN mkdir -p /hana/mounts && \
    chown -R 12000:79 /hana/mounts && \
    chmod -R 775 /hana/mounts

# Expose essential ports
EXPOSE 39013 39015 39017 51000 51001 51060 53075

# Simple health check to verify HANA is running
HEALTHCHECK --interval=60s --timeout=20s --retries=10 \
  CMD /bin/bash -c "pgrep -f hdbnameserver >/dev/null || exit 1"
