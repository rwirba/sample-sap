FROM registry.access.redhat.com/ubi9/ubi AS build
RUN dnf -y install java-17-openjdk-devel maven && dnf clean all && rm -rf /var/cache/dnf
WORKDIR /src
COPY pom.xml .
RUN mvn -B -q -DskipTests dependency:go-offline
COPY src ./src
RUN mvn -B -DskipTests package

FROM registry.access.redhat.com/ubi9/openjdk-17-runtime
USER 0
RUN mkdir -p /opt/app && chown -R 10001:0 /opt/app
COPY --from=build /src/target/java-ads-demo-*.jar /opt/app/app.jar
EXPOSE 8080
USER 10001
ENTRYPOINT ["java","-jar","/opt/app/app.jar"]
