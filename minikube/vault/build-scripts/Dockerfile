FROM ubuntu:22.04

RUN apt-get update && apt-get install -y unzip curl jq

ENV VAULT_VERSION=1.15.0

RUN curl -fsSL https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip -o vault.zip && \
    unzip vault.zip && mv vault /usr/local/bin/ && chmod +x /usr/local/bin/vault

HEALTHCHECK --interval=30s --timeout=5s --retries=5 CMD curl -fsS http://127.0.0.1:8200/v1/sys/health || exit 1
CMD ["vault", "server", "-dev", "-dev-listen-address=0.0.0.0:8200", "-dev-root-token-id=root"]    
