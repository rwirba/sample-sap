FROM docker.io/library/mysql:8.0

ENV MYSQL_ROOT_PASSWORD=rootpass \
    MYSQL_DATABASE=demodb \
    MYSQL_USER=demo \
    MYSQL_PASSWORD=demopass

COPY init.sql /docker-entrypoint-initdb.d/init.sql
EXPOSE 3306
