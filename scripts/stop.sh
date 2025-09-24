#!/usr/bin/env bash
# Shutdown script for Jenkins-Vault POC
# Gracefully stops containers

set -euo pipefail

echo "Shutting down Jenkins-Vault POC..."

# Stop containers gracefully
echo "Stopping Docker containers..."
docker compose down

echo "Shutdown complete!"
echo "   All data is preserved in ./data/ directory"
echo "   Use './scripts/start.sh' to restart with data intact"