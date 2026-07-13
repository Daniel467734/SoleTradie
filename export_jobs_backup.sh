#!/bin/zsh

# Export Firestore Jobs to JSON Backup
# This script uses Firebase CLI to export your jobs collection
# Run this BEFORE deleting local jobs

set -e

echo "🔐 Firestore Jobs Export Script"
echo "================================"
echo ""

# Check if firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not found. Install with: npm install -g firebase-tools"
    exit 1
fi

# Check if user is authenticated
firebase auth:list 2>/dev/null || {
    echo "⚠️ Not authenticated to Firebase. Run: firebase login"
    exit 1
}

# Create backup directory
BACKUP_DIR="$HOME/SOLE TRADER APP VERSIONS/Version 2.2/backup"
mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/jobs_backup_${TIMESTAMP}.json"

echo "📦 Exporting jobs from Firestore..."
echo "📁 Output: $BACKUP_FILE"
echo ""

# Note: Direct Firestore export requires Google Cloud SDK
# Alternative: Use the app itself to export via debug menu

echo "⚠️ Note: Automatic export requires Google Cloud SDK (gcloud)"
echo ""
echo "Alternative options:"
echo "1. Via Firebase Console:"
echo "   - Go to: Firebase Console → Firestore Database → jobs collection"
echo "   - Export each job manually"
echo ""
echo "2. Via App Debug Menu:"
echo "   - Open the app"
echo "   - Go to Settings → Debug → Export Jobs to JSON"
echo "   - This will save jobs_export.json to device storage"
echo ""
echo "3. Via ADB (Android):"
echo "   adb pull /data/data/com.example.app/app_flutter/jobs.json $BACKUP_FILE"
echo ""

# If using Google Cloud SDK
if command -v gcloud &> /dev/null; then
    echo "📥 Attempting export with Google Cloud SDK..."
    # This would require proper setup - for now just guide the user
    echo "To use gcloud, run:"
    echo "  gcloud firestore export $BACKUP_DIR --collection-ids=jobs"
fi

echo ""
echo "✅ When you have the backup saved, run:"
echo "   zsh delete_and_restore_jobs.sh"
