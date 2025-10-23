#!/bin/bash
set -e

echo "🔄 Updating ads-java-demo deployment..."

# Upgrade the Helm release
helm upgrade ads-java ./ads-java-chart --namespace demo

echo "✅ ads-java-demo updated successfully."