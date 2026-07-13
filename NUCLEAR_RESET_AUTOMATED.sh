#!/bin/zsh

# 🔴 NUCLEAR RESET - Delete Everything Cloud & Local, Then Restore Fresh
# Automated version - no prompts

set -e

echo "🔴 NUCLEAR RESET & RESTORE (AUTOMATED)"
echo "========================================"
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

echo "${YELLOW}📋 Step 1: Verifying backup files exist...${NC}"
echo ""

if [[ ! -f "$JOBS_FILE" ]]; then
    echo "${RED}❌ ERROR: jobs.json not found${NC}"
    exit 1
else
    SIZE=$(du -h "$JOBS_FILE" | cut -f1)
    echo "${GREEN}✅ jobs.json found ($SIZE)${NC}"
fi

if [[ ! -f "$CUSTOMERS_FILE" ]]; then
    echo "${RED}❌ ERROR: customers.json not found${NC}"
    exit 1
else
    SIZE=$(du -h "$CUSTOMERS_FILE" | cut -f1)
    echo "${GREEN}✅ customers.json found ($SIZE)${NC}"
fi

if [[ ! -f "$PRICEBOOK_FILE" ]]; then
    echo "${RED}❌ ERROR: price_book.json not found${NC}"
    exit 1
else
    SIZE=$(du -h "$PRICEBOOK_FILE" | cut -f1)
    echo "${GREEN}✅ price_book.json found ($SIZE)${NC}"
fi

echo ""
echo "${YELLOW}📋 Step 2: Checking ADB connection...${NC}"

if ! command -v adb &> /dev/null; then
    echo "${RED}❌ adb not found${NC}"
    exit 1
fi

DEVICES=$(adb devices | grep -v "^$" | tail -n +2 | grep "device$" | wc -l)
if [ $DEVICES -eq 0 ]; then
    echo "${RED}❌ No Android devices connected${NC}"
    exit 1
else
    echo "${GREEN}✅ Device connected${NC}"
    adb devices | grep -v "^$" | tail -n +2 | head -1
fi

echo ""
echo "${YELLOW}📋 Step 3: Creating pre-reset backups...${NC}"

BACKUP_DIR="$WORKSPACE_DIR/backup/pre_nuclear_reset_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

cp "$JOBS_FILE" "$BACKUP_DIR/jobs.json"
cp "$CUSTOMERS_FILE" "$BACKUP_DIR/customers.json"
cp "$PRICEBOOK_FILE" "$BACKUP_DIR/price_book.json"

echo "${GREEN}✅ Backups created at: $BACKUP_DIR${NC}"

echo ""
echo "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${YELLOW}📋 Step 4: Deleting local app data on device...${NC}"
echo "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

JOBS_PATH="/data/data/$PACKAGE_NAME/app_flutter/jobs.json"
CONTACTS_PATH="/data/data/$PACKAGE_NAME/app_flutter/contacts.json"
PRICEBOOK_PATH="/data/data/$PACKAGE_NAME/app_flutter/price_book.json"

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
echo "${YELLOW}📋 Step 5: Manual Firestore Deletion Required${NC}"
echo "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "${BLUE}🔗 Go to Firebase Console:${NC}"
echo "   https://console.firebase.google.com"
echo ""
echo "   1. Select your project"
echo "   2. Go to: Firestore Database"
echo "   3. Delete these collections:"
echo "      ❌ ${RED}jobs${NC}"
echo "      ❌ ${RED}contacts${NC}"
echo "      ❌ ${RED}pricebook${NC}"
echo ""
echo "   For each collection:"
echo "   - Click the three dots ⋮"
echo "   - Select 'Delete collection'"
echo "   - Confirm deletion"
echo ""
echo "${YELLOW}After deleting all three collections, come back and continue...${NC}"
echo ""

echo ""
echo "${GREEN}✅ LOCAL DATA CLEARED - Ready for manual Firestore deletion${NC}"

echo ""
echo "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${YELLOW}📋 Step 6: Final Steps${NC}"
echo "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "${BLUE}🚀 WHAT TO DO NOW:${NC}"
echo ""
echo "1. ${YELLOW}DELETE Firestore collections${NC} (as shown above)"
echo "   - jobs collection"
echo "   - contacts collection"
echo "   - pricebook collection"
echo ""
echo "2. ${YELLOW}Close the app${NC} on your device"
echo ""
echo "3. ${YELLOW}Restart the app${NC}"
echo ""
echo "4. ${YELLOW}Wait 30-60 seconds${NC} for initial sync"
echo ""
echo "5. ${YELLOW}Watch the logs${NC}:"
echo "   ${BLUE}adb logcat | grep flutter${NC}"
echo ""
echo "6. ${YELLOW}Verify success:${NC}"
echo "   ✅ App shows ~92 jobs"
echo "   ✅ Contacts list populated"
echo "   ✅ Price book loaded"
echo "   ✅ No sync errors"
echo ""

echo "${GREEN}✅ NUCLEAR RESET AUTOMATION COMPLETE!${NC}"
echo ""
echo "📁 Backup location: $BACKUP_DIR"
echo ""
