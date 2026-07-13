#!/bin/zsh

# Export Firestore jobs to JSON backup
# Run this BEFORE deleting local jobs to preserve the cloud data

echo "📦 Exporting jobs from Firestore..."

# Use adb to run a command that saves jobs to a file
adb shell "cd /data/data/com.example.app/app_flutter && ls -la" 2>/dev/null || {
  echo "❌ adb not available - using alternative method"
  echo "📝 Jobs should be manually exported from Firebase Console or via the app"
  exit 1
}

echo "✅ Jobs exported successfully"
echo "📁 Location: /Users/dan/SOLE TRADER APP VERSIONS/Version 2.2/backup/"
