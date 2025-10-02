FROM docker.io/library/postgres:16
LABEL org.opencontainers.image.title="hana-standin" \
      org.opencontainers.image.description="PostgreSQL-based stand-in to demo StatefulSet/PVC in place of SAP HANA" \
      org.opencontainers.image.vendor="demo"
# Default Postgres port; when you RUN the container manually later, you can map -p 39013:5432 to mimic HANA-style ports.
EXPOSE 5432
# Optional: place init SQL here if you want demo tables
# COPY initdb/* /docker-entrypoint-initdb.d/
