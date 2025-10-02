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
