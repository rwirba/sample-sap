# Wrapper image for SAP HANA, express edition
ARG HXE_BASE_IMAGE=docker.io/saplabs/hanaexpress:latest
FROM ${HXE_BASE_IMAGE}

LABEL org.opencontainers.image.title="SAP HANA Express Wrapper" \
      org.opencontainers.image.description="Custom wrapper for HANA Express built via Ansible" \
      maintainer="ryandevlab"

# Accept EULA and set locale explicitly
ENV HANA_LICENSE=accept \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# Expose the main HANA web & DB ports (optional)
EXPOSE 39013 39015 39017 51000 51060 53075

# Keep SAP's original entrypoint and command
# We do NOT override CMD or ENTRYPOINT here, SAP’s image handles startup.
