# Save inside k1 (e.g., /usr/local/bin/build_java_image.sh) and chmod +x it
#!/usr/bin/env bash
set -euo pipefail

# --- knobs ---
APP_DIR="${APP_DIR:-/workspace/java-ads-demo}"
IMAGE_NAME="${IMAGE_NAME:-java-ads-demo}"
IMAGE_TAG="${IMAGE_TAG:-0.1}"

echo "[java] Scaffolding sources at: $APP_DIR"
mkdir -p "$APP_DIR/src/main/java/com/example"
cd "$APP_DIR"

# Dockerfile (UBI9 build + UBI9 runtime, non-root runtime user)
cat > Dockerfile <<'EOF'
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
EOF

# Minimal app: /health and /pdf
cat > src/main/java/com/example/App.java <<'EOF'
package com.example;
import com.sun.net.httpserver.*;
import java.io.*; import java.net.*; import java.nio.charset.StandardCharsets;
public class App {
  public static void main(String[] a) throws Exception {
    HttpServer s = HttpServer.create(new InetSocketAddress(8080), 0);
    s.createContext("/health", ex -> respond(ex, 200, "OK", "text/plain"));
    s.createContext("/pdf", ex -> {
      byte[] pdf = ("%PDF-1.4\n1 0 obj<<>>endobj\n2 0 obj<<>>endobj\n3 0 obj<< /Type /Page /Parent 2 0 R /Resources <<>> /MediaBox [0 0 200 200] /Contents 4 0 R >>endobj\n4 0 obj<< /Length 44 >>stream\nBT /F1 24 Tf 50 150 Td (Hello, Adobe demo!) Tj ET\nendstream endobj\n5 0 obj<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>endobj\n2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj\n6 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\nxref\n0 7\n0000000000 65535 f \n0000000010 00000 n \n0000000053 00000 n \n0000000104 00000 n \n0000000254 00000 n \n0000000372 00000 n \n0000000453 00000 n \ntrailer<< /Root 6 0 R /Size 7 >>\nstartxref\n530\n%%EOF").getBytes(StandardCharsets.US_ASCII);
      ex.getResponseHeaders().add("Content-Type","application/pdf");
      ex.sendResponseHeaders(200, pdf.length); try(OutputStream os=ex.getResponseBody()){ os.write(pdf); }
    });
    s.start(); System.out.println("Listening :8080");
  }
  static void respond(HttpExchange ex, int code, String body, String ct) throws IOException {
    ex.getResponseHeaders().add("Content-Type", ct);
    byte[] b = body.getBytes(StandardCharsets.UTF_8);
    ex.sendResponseHeaders(code, b.length); try(OutputStream os=ex.getResponseBody()){ os.write(b); }
  }
}
EOF

# Maven POM
cat > pom.xml <<'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>java-ads-demo</artifactId>
  <version>0.1.0</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
  <dependencies/>
  <build>
    <plugins>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-jar-plugin</artifactId>
        <version>3.3.0</version>
        <configuration>
          <archive><manifest><mainClass>com.example.App</mainClass></manifest></archive>
        </configuration>
      </plugin>
    </plugins>
  </build>
</project>
EOF

echo "[java] Building image ${IMAGE_NAME}:${IMAGE_TAG} ..."
podman build -t "${IMAGE_NAME}:${IMAGE_TAG}" .

echo "[java] Built image:"
podman images | awk 'NR==1 || $1 ~ /'"${IMAGE_NAME}"'/'
echo "[java] To push later: podman tag ${IMAGE_NAME}:${IMAGE_TAG} <ACR_NAME>.azurecr.io/demo/${IMAGE_NAME}:${IMAGE_TAG}"

