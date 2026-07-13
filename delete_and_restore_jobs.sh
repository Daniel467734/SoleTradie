#!/bin/zsh

# Delete Local Jobs & Restore from Firestore Backup
# This script will:
# 1. Delete local jobs.json
# 2. Clear app cache
# 3. Restart app to trigger cloud sync

set -e

echo "🚀 Job Restoration Script"
echo "========================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PACKAGE_NAME="com.example.app"
JOBS_FILE_PATH="/data/data/$PACKAGE_NAME/app_flutter/jobs.json"

echo "⚠️  IMPORTANT STEPS BEFORE CONTINUING:"
echo "1. ✅ Verify all 92 jobs are in Firebase Console (Firestore Database)"
echo "2. ✅ Ensure app is built with ALL THREE FIXES applied"
echo "3. ✅ Have a backup of jobs_backup.json saved locally"
echo "4. ✅ Device/emulator is connected and accessible via ADB"
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "📋 Step 1: Checking ADB connection..."

if ! command -v adb &> /dev/null; then
    echo "${RED}❌ adb not found. Install Android SDK.${NC}"
    exit 1
fi

# Check for connected devices
DEVICES=$(adb devices | grep -v "^$" | tail -n +2 | grep -v "List of attached" | wc -l)
if [ $DEVICES -eq 0 ]; then
    echo "${RED}❌ No Android devices/emulators connected.${NC}"
    echo "Connect a device or start an emulator, then run this script again."
    exit 1
fi

echo "${GREEN}✅ Device connected${NC}"
adb devices

echo ""
echo "📋 Step 2: Verifying jobs.json exists locally..."

if adb shell test -f "$JOBS_FILE_PATH"; then
    echo "${GREEN}✅ Found local jobs.json${NC}"
    LOCAL_SIZE=$(adb shell stat -c%s "$JOBS_FILE_PATH" 2>/dev/null || echo "unknown")
    echo "   Size: $LOCAL_SIZE bytes"
else
    echo "${YELLOW}⚠️  Local jobs.json not found (might already be deleted)${NC}"
fi

echo ""
echo "📋 Step 3: Creating backup of local jobs (just in case)..."

BACKUP_DIR="$HOME/SOLE TRADER APP VERSIONS/Version 2.2/backup"
mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOCAL_BACKUP="$BACKUP_DIR/jobs_local_backup_before_delete_${TIMESTAMP}.json"

if adb shell test -f "$JOBS_FILE_PATH"; then
    adb pull "$JOBS_FILE_PATH" "$LOCAL_BACKUP" 2>&1 | grep -v "^$" || true
    echo "${GREEN}✅ Local backup saved to:${NC}"
    echo "   $LOCAL_BACKUP"
else
    echo "${YELLOW}⚠️  Skipping local backup (file doesn't exist)${NC}"
fi

echo ""
echo "📋 Step 4: Deleting local jobs.json..."

if adb shell test -f "$JOBS_FILE_PATH"; then
    adb shell rm "$JOBS_FILE_PATH"
    echo "${GREEN}✅ Deleted local jobs.json${NC}"
    
    # Verify deletion
    if ! adb shell test -f "$JOBS_FILE_PATH"; then
        echo "${GREEN}✅ Verified: jobs.json successfully deleted${NC}"
    else
        echo "${RED}❌ ERROR: jobs.json still exists!${NC}"
        exit 1
    fi
else
    echo "${YELLOW}⚠️  jobs.json didn't exist (nothing to delete)${NC}"
fi

echo ""
echo "📋 Step 5: Clearing app cache..."

adb shell pm clear "$PACKAGE_NAME" 2>&1 | grep -v "^$" || true
echo "${GREEN}✅ App cache cleared${NC}"

echo ""
echo "📋 Step 6: Manual Step - Restart the app"
echo ""
echo "${YELLOW}⚠️  IMPORTANT - Do these steps manually:${NC}"
echo ""
echo "1. Close the app (if running)"
echo "2. Restart the app"
echo "3. App will detect missing local jobs.json"
echo "4. App will automatically sync from Firestore"
echo "5. Wait for sync to complete (check logs for '✅ Synced X jobs')"
echo ""

echo "${GREEN}Expected log messages to see:${NC}"
echo "   ✅ Loaded X jobs from Firestore"
echo "   ✅ Saved X jobs to local storage (atomic write)"
echo "   ✅ Synced X jobs from Firebase (delta sync)"
echo ""

echo "${YELLOW}📱 To see logs on Android device:${NC}"
echo "   adb logcat | grep flutter"
echo ""

echo ""
echo "✅ Script complete!"
echo ""
echo "📋 Verification steps:"
echo "1. Open app"
echo "2. Wait 30-60 seconds for initial sync"
echo "3. Verify jobs list shows ~92 jobs"
echo "4. Tap a few jobs to verify invoices are present"
echo "5. Generate a new invoice to test"
echo ""

echo "🎉 Done! Your jobs should now be restored from Firestore."
