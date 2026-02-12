#!/bin/zsh
set -euo pipefail

echo "Notarization is not configured for this project yet."
echo "Configure Apple Developer credentials and update scripts/notarize.sh."
echo "Expected inputs usually include: TEAM_ID, APPLE_ID (or API key), and app-specific password or key file."
exit 1
