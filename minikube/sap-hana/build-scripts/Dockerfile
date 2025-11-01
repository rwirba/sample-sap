# ---------------------------------------------------------------
# SAP HANA Express Base Edition Wrapper (DB-only)
# ---------------------------------------------------------------
ARG HXE_BASE_IMAGE=docker.io/saplabs/hanaexpress:2.00.082.00.20250528.1
FROM ${HXE_BASE_IMAGE}

LABEL org.opencontainers.image.title="SAP HANA Express Wrapper (DB-only)" \
      org.opencontainers.image.description="Lightweight SAP HANA Express container with persistence, managed via Podman." \
      maintainer="Ryab W"

ENV HANA_LICENSE=accept \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TZ=UTC

# Prepare mounts for persistence
RUN mkdir -p /hana/mounts \
    && chown -R 12000:79 /hana/mounts \
    && chmod -R 775 /hana/mounts

EXPOSE 39013 39015 39017

HEALTHCHECK --interval=60s --timeout=20s --retries=10 \
  CMD /bin/bash -c "pgrep -f hdbnameserver >/dev/null || exit 1"
