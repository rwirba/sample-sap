# Wrapper image for SAP HANA, express edition
ARG HXE_BASE_IMAGE=docker.io/saplabs/hanaexpress:latest
FROM ${HXE_BASE_IMAGE}

LABEL org.opencontainers.image.title="SAP HANA Express Wrapper" \
      org.opencontainers.image.description="Custom wrapper for HANA Express built via Ansible" \
      maintainer="ryandevlab"

# No CMD override; SAP’s entrypoint manages startup
