# ---------------------------------------------------------------------
# SAP HANA Express Full Edition Wrapper (Server + XS Advanced + Cockpit)
# Base image must include Web IDE / Cockpit runtime
# Author: Ryan DevLab
# ---------------------------------------------------------------------

# Use the full-edition image that includes XS Engine and Web Cockpit
ARG HXE_BASE_IMAGE=docker.io/saplabs/hanaexpress:2.00.061.00.20220519.1
FROM ${HXE_BASE_IMAGE}

LABEL org.opencontainers.image.title="SAP HANA Express Wrapper (Full Edition)" \
      org.opencontainers.image.description="Custom wrapper on top of SAP HANA Express full edition, with XS Advanced and Cockpit enabled." \
      maintainer="ryandevlab"

# ---------------------------------------------------------------------
# Environment setup
# ---------------------------------------------------------------------
ENV HANA_LICENSE=accept \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TZ=UTC

# Ensure necessary directories exist and have correct ownership
# (HANA expects /hana/mounts to be writable by UID 12000:GID 79)
RUN mkdir -p /hana/mounts && \
    chown -R 12000:79 /hana && \
    chmod -R 775 /hana

# ---------------------------------------------------------------------
# Expose SAP HANA core ports
# ---------------------------------------------------------------------
# 39013 - Index server internal
# 39015 - SQL port (SYSTEMDB)
# 39017 - SQL port (tenant)
# 51000–51060 - XS/Web Cockpit
# 53075 - Web Dispatcher Admin
EXPOSE 39013 39015 39017 51000 51060 53075

# ---------------------------------------------------------------------
# Healthcheck – verify nameserver port is reachable
# ---------------------------------------------------------------------
HEALTHCHECK --interval=60s --timeout=20s --retries=10 \
  CMD /bin/bash -c "pgrep -f hdbnameserver >/dev/null || exit 1"

# ---------------------------------------------------------------------
# Keep SAP's original entrypoint and command.
# We do NOT override CMD or ENTRYPOINT — SAP manages startup.
# ---------------------------------------------------------------------

