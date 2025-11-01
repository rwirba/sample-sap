
# ARG HXE_BASE_IMAGE=docker.io/saplabs/hanaexpress:2.00.061.00.20220519.1
# FROM ${HXE_BASE_IMAGE}

# LABEL org.opencontainers.image.title="SAP HANA Express Wrapper (Full Edition)" \
#       org.opencontainers.image.description="Custom wrapper on top of SAP HANA Express full edition, with XS Advanced and Cockpit enabled." \
#       maintainer="ryandevlab"


# ENV HANA_LICENSE=accept \
#     LANG=en_US.UTF-8 \
#     LC_ALL=en_US.UTF-8 \
#     TZ=UTC

# RUN mkdir -p /hana/mounts && \
#     chown -R 12000:79 /hana && \
#     chmod -R 775 /hana


# EXPOSE 39013 39015 39017 51000 51060 53075


# HEALTHCHECK --interval=60s --timeout=20s --retries=10 \
#   CMD /bin/bash -c "pgrep -f hdbnameserver >/dev/null || exit 1"

ARG HXE_BASE_IMAGE=docker.io/saplabs/hanaexpress:2.00.082.00.20250528.1
FROM ${HXE_BASE_IMAGE}

LABEL org.opencontainers.image.title="SAP HANA Express Wrapper" \
      org.opencontainers.image.description="Custom wrapper for HANA Express built via Ansible" \
      maintainer="ryandevlab"

ENV HANA_LICENSE=accept \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

EXPOSE 39013 39015 39017 51000 51060 53075



