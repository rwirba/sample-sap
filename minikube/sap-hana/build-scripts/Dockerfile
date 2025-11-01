ARG HXE_BASE_IMAGE=docker.io/saplabs/hanaexpress:2.00.082.00.20250528.1
FROM ${HXE_BASE_IMAGE}

LABEL org.opencontainers.image.title="SAP HANA Express Wrapper" \
      org.opencontainers.image.description="Light wrapper image for SAP HANA Express with persistence and post-start automation." \
      maintainer="ryandevlab"

ENV HANA_LICENSE=accept \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TZ=UTC

RUN mkdir -p /hana/mounts && \
    chown -R 12000:79 /hana/mounts && \
    chmod -R 775 /hana/mounts

EXPOSE 39013 39015 39017 51000 51001 51060 53075

HEALTHCHECK --interval=60s --timeout=20s --retries=10 \
  CMD /bin/bash -c "pgrep -f hdbnameserver >/dev/null || exit 1"
