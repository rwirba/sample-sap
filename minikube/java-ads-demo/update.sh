#!/bin/bash
set -e

echo "🔄 Updating java-ads-demo deployment..."

# Upgrade the Helm release
helm upgrade ads-java ./ads-java-chart --namespace demo

echo "✅ java-ads-demo updated successfully."