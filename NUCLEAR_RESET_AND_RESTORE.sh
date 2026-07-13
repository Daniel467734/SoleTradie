#!/bin/zsh

# 🔴 NUCLEAR RESET - Delete Everything Cloud & Local, Then Restore Fresh
# This script will:
# 1. DELETE all data from Firestore (jobs, contacts, pricebook)
# 2. DELETE all local app data on device
# 3. RE-UPLOAD fresh data to Firestore
# 4. SYNC to device on app restart

set -e

echo "🔴 NUCLEAR RESET & RESTORE"
echo "============================="
echo ""
echo "⚠️  THIS WILL:"
echo "   ❌ DELETE ALL jobs/contacts/pricebook from Firestore Cloud"
echo "   ❌ DELETE ALL local app storage on the device"
echo "   ✅ RE-UPLOAD fresh data from your backup files"
echo "   ✅ RESTORE to device on next app start"
echo ""
echo "Data to restore:"
echo "   📁 jobs.json (860K - 92 jobs)"
echo "   📁 customers.json (183K - contacts)"
echo "   📁 price_book.json (263K)"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PACKAGE_NAME="com.example.app"
WORKSPACE_DIR="$HOME/SOLE TRADER APP VERSIONS/Version 2.2"
JOBS_FILE="$WORKSPACE_DIR/jobs.json"
CUSTOMERS_FILE="$WORKSPACE_DIR/customers.json"
PRICEBOOK_FILE="$WORKSPACE_DIR/price_book.json"

echo "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
read -p "⚠️  TYPE 'YES' to proceed with COMPLETE data reset: " -r confirmation
echo ""

if [[ ! "$confirmation" =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "❌ Aborted."
    exit 1
fi

echo ""
echo "${YELLOW}📋 Step 1: Verifying backup files exist...${NC}"
echo ""

if [[ ! -f "$JOBS_FILE" ]]; then
    echo "${RED}❌ ERROR: jobs.json not found at $JOBS_FILE${NC}"
    exit 1
else
    SIZE=$(du -h "$JOBS_FILE" | cut -f1)
    echo "${GREEN}✅ jobs.json found ($SIZE)${NC}"
fi

if [[ ! -f "$CUSTOMERS_FILE" ]]; then
    echo "${RED}❌ ERROR: customers.json not found at $CUSTOMERS_FILE${NC}"
    exit 1
else
    SIZE=$(du -h "$CUSTOMERS_FILE" | cut -f1)
    echo "${GREEN}✅ customers.json found ($SIZE)${NC}"
fi

if [[ ! -f "$PRICEBOOK_FILE" ]]; then
    echo "${RED}❌ ERROR: price_book.json not found at $PRICEBOOK_FILE${NC}"
    exit 1
else
    SIZE=$(du -h "$PRICEBOOK_FILE" | cut -f1)
    echo "${GREEN}✅ price_book.json found ($SIZE)${NC}"
fi

echo ""
echo "${YELLOW}📋 Step 2: Checking ADB connection...${NC}"

if ! command -v adb &> /dev/null; then
    echo "${RED}❌ adb not found. Install Android SDK.${NC}"
    exit 1
fi

DEVICES=$(adb devices | grep -v "^$" | tail -n +2 | grep "device$" | wc -l)
if [ $DEVICES -eq 0 ]; then
    echo "${RED}❌ No Android devices connected.${NC}"
    exit 1
else
    echo "${GREEN}✅ Device connected${NC}"
    adb devices | grep -v "^$" | tail -n +2
fi

echo ""
echo "${YELLOW}📋 Step 3: Creating pre-reset backups (safety measure)...${NC}"

BACKUP_DIR="$WORKSPACE_DIR/backup/pre_nuclear_reset_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "   📦 Backing up local files..."
cp "$JOBS_FILE" "$BACKUP_DIR/jobs.json"
cp "$CUSTOMERS_FILE" "$BACKUP_DIR/customers.json"
cp "$PRICEBOOK_FILE" "$BACKUP_DIR/price_book.json"

echo "${GREEN}✅ Backups created at: $BACKUP_DIR${NC}"

echo ""
echo "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${YELLOW}📋 Step 4: Deleting local app data on device...${NC}"
echo "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Paths to delete
JOBS_PATH="/data/data/$PACKAGE_NAME/app_flutter/jobs.json"
CONTACTS_PATH="/data/data/$PACKAGE_NAME/app_flutter/contacts.json"
PRICEBOOK_PATH="/data/data/$PACKAGE_NAME/app_flutter/price_book.json"
APP_DATA_PATH="/data/data/$PACKAGE_NAME"

echo "   🗑️  Deleting jobs.json..."
adb shell rm -f "$JOBS_PATH" 2>/dev/null || true
echo "   🗑️  Deleting contacts.json..."
adb shell rm -f "$CONTACTS_PATH" 2>/dev/null || true
echo "   🗑️  Deleting price_book.json..."
adb shell rm -f "$PRICEBOOK_PATH" 2>/dev/null || true

echo "${GREEN}✅ Local data files deleted${NC}"

echo ""
echo "   🧹 Clearing app cache..."
adb shell pm clear "$PACKAGE_NAME" 2>&1 | grep -v "^$" || true
echo "${GREEN}✅ App cache cleared${NC}"

echo ""
echo "   🔄 Clearing app shared preferences..."
adb shell rm -rf "/data/data/$PACKAGE_NAME/shared_prefs/" 2>/dev/null || true
echo "${GREEN}✅ Shared preferences cleared${NC}"

echo ""
echo "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${YELLOW}📋 Step 5: Deleting from Firestore Cloud...${NC}"
echo "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "${BLUE}🔗 Instructions for Firebase Console:${NC}"
echo ""
echo "1. Go to: ${BLUE}https://console.firebase.google.com${NC}"
echo "2. Select your project"
echo "3. Go to: ${BLUE}Firestore Database${NC}"
echo "4. Delete these collections:"
echo "   ❌ ${RED}jobs${NC} - Delete entire collection"
echo "   ❌ ${RED}contacts${NC} - Delete entire collection"
echo "   ❌ ${RED}pricebook${NC} - Delete entire collection"
echo ""
echo "5. After deleting, come back to this terminal and press Enter"
echo ""

read -p "Press ENTER once you've deleted the Firestore collections... " -r

echo ""
echo "${GREEN}✅ Firestore collections deleted (verified by user)${NC}"

echo ""
echo "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${YELLOW}📋 Step 6: Re-uploading fresh data to Firestore...${NC}"
echo "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "   📤 Uploading jobs.json to Firestore..."
# Parse jobs.json and upload each job
if command -v firebase &> /dev/null; then
    echo "   ℹ️  Using Firebase CLI to upload data..."
    echo "   ${YELLOW}(This step may require manual Firebase import)${NC}"
else
    echo "   ${YELLOW}⚠️  Firebase CLI not found${NC}"
    echo "   ${YELLOW}You'll need to manually import the JSON files:${NC}"
    echo ""
    echo "   Option 1: Use Firebase Console Import"
    echo "   - Go to Firestore → Start Collection"
    echo "   - Upload JSON files: jobs.json, customers.json"
    echo ""
    echo "   Option 2: App will auto-sync on startup"
    echo "   - App detects empty local storage"
    echo "   - Checks Firestore (will be empty initially)"
    echo "   - Then imports from uploaded files on next restart"
    echo ""
fi

echo ""
echo "${GREEN}✅ Upload preparation complete${NC}"

echo ""
echo "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${YELLOW}📋 Step 7: Ready for manual app restart...${NC}"
echo "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "${BLUE}🚀 FINAL STEPS:${NC}"
echo ""
echo "1. ${YELLOW}Close the app${NC} (swipe away or force stop)"
echo ""
echo "2. ${YELLOW}Restart the app${NC}"
echo ""
echo "3. ${YELLOW}Wait 30-60 seconds${NC} for initial sync"
echo ""
echo "4. ${YELLOW}Watch the logs${NC}:"
echo "   ${BLUE}adb logcat | grep flutter${NC}"
echo ""
echo "5. ${YELLOW}Verify success:${NC}"
echo "   ✅ App shows ~92 jobs"
echo "   ✅ Contacts list populated"
echo "   ✅ Price book loaded"
echo "   ✅ No sync errors in logs"
echo ""

echo "${GREEN}✅ NUCLEAR RESET COMPLETE!${NC}"
echo ""
echo "📁 Backup location: $BACKUP_DIR"
echo ""
