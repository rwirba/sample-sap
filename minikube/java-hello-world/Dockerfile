FROM docker.io/library/eclipse-temurin:17-jdk-alpine
WORKDIR /app
COPY target/java-hello-world-1.0.0.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]