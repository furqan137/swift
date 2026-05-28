#!/bin/bash
echo "=== FILE SIZES (lines) ==="
find "/Users/pauljoseph/BeeClean/apps/frontend/BeeClean" -name "*.swift" -exec wc -l {} + | sort -rn | head -50
echo ""
echo "=== DIRECTORY STRUCTURE ==="
find "/Users/pauljoseph/BeeClean/apps/frontend/BeeClean" -type f -name "*.swift" | sort
echo ""
echo "=== BACKEND FILES ==="
find "/Users/pauljoseph/BeeClean/apps/backend/src" -type f -name "*.ts" -exec wc -l {} + | sort -rn | head -20
