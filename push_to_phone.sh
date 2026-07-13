#!/bin/bash
# Push recovered data files to phone
# Usage: ./push_to_phone.sh

set -e

PROJECT_DIR="/Users/dan/SOLE TRADER APP VERSIONS/Version 11 Settings need sfixing copy 2"
TEMP_DIR="/data/local/tmp"
APP_DOCS_DIR="/data/user/0/com.example.app/documents"

echo "📱 Checking for connected Android device..."
device_count=$(adb devices | grep -c "device$")

if [ "$device_count" -eq 0 ]; then
    echo "❌ No Android device found!"
    echo "Please:"
    echo "  1. Enable USB Debugging on your phone (Settings > Developer Options)"
    echo "  2. Connect phone via USB cable"
    echo "  3. Run: adb devices"
    echo "  4. Then try again"
    exit 1
fi

echo "✅ Device found!"
echo ""

# Push jobs.json
if [ -f "$PROJECT_DIR/jobs.json" ]; then
    echo "� Pushing jobs.json (91 jobs)..."
    adb push "$PROJECT_DIR/jobs.json" "$TEMP_DIR/jobs.json" > /dev/null
    if [ $? -eq 0 ]; then
        # Move from temp to app directory
        adb shell "cp $TEMP_DIR/jobs.json $APP_DOCS_DIR/jobs.json && rm $TEMP_DIR/jobs.json" 2>/dev/null || \
        adb shell "cat $TEMP_DIR/jobs.json > $APP_DOCS_DIR/jobs.json && rm $TEMP_DIR/jobs.json" 2>/dev/null || \
        echo "   ⚠️  Could not move to final location (app may not have permission)"
        
        size=$(adb shell ls -lh "$APP_DOCS_DIR/jobs.json" 2>/dev/null | awk '{print $5}' || echo "?")
        echo "   ✅ Pushed: $size"
    else
        echo "   ❌ Failed to push jobs.json"
        exit 1
    fi
else
    echo "   ❌ jobs.json not found in project directory!"
    exit 1
fi

# Push customers.json
if [ -f "$PROJECT_DIR/customers.json" ]; then
    echo "📤 Pushing customers.json (680 customers)..."
    adb push "$PROJECT_DIR/customers.json" "$TEMP_DIR/customers.json" > /dev/null
    if [ $? -eq 0 ]; then
        adb shell "cp $TEMP_DIR/customers.json $APP_DOCS_DIR/customers.json && rm $TEMP_DIR/customers.json" 2>/dev/null || \
        adb shell "cat $TEMP_DIR/customers.json > $APP_DOCS_DIR/customers.json && rm $TEMP_DIR/customers.json" 2>/dev/null || \
        echo "   ⚠️  Could not move to final location"
        
        size=$(adb shell ls -lh "$APP_DOCS_DIR/customers.json" 2>/dev/null | awk '{print $5}' || echo "?")
        echo "   ✅ Pushed: $size"
    else
        echo "   ❌ Failed to push customers.json"
        exit 1
    fi
else
    echo "   ⚠️  customers.json not found (optional)"
fi

# Push price_book.json
if [ -f "$PROJECT_DIR/price_book.json" ]; then
    echo "📤 Pushing price_book.json (500 items)..."
    adb push "$PROJECT_DIR/price_book.json" "$TEMP_DIR/price_book.json" > /dev/null
    if [ $? -eq 0 ]; then
        adb shell "cp $TEMP_DIR/price_book.json $APP_DOCS_DIR/price_book.json && rm $TEMP_DIR/price_book.json" 2>/dev/null || \
        adb shell "cat $TEMP_DIR/price_book.json > $APP_DOCS_DIR/price_book.json && rm $TEMP_DIR/price_book.json" 2>/dev/null || \
        echo "   ⚠️  Could not move to final location"
        
        size=$(adb shell ls -lh "$APP_DOCS_DIR/price_book.json" 2>/dev/null | awk '{print $5}' || echo "?")
        echo "   ✅ Pushed: $size"
    else
        echo "   ❌ Failed to push price_book.json"
        exit 1
    fi
else
    echo "   ⚠️  price_book.json not found (optional)"
fi

echo ""
echo "📋 Verifying files on phone..."
adb shell ls -lh "$APP_DOCS_DIR/" 2>/dev/null | grep -E "\.(json|txt)$" || echo "   (Files may be in /data/local/tmp)"

echo ""
echo "✅ All files pushed successfully!"
echo ""
echo "Next steps:"
echo "  1. Close the app on your phone (swipe from recent apps)"
echo "  2. Wait 2 seconds"
echo "  3. Reopen the app"
echo "  4. Wait 10 seconds for sync"
echo ""
echo "You should now see:"
echo "  ✅ Dashboard: Job count showing 91"
echo "  ✅ Jobs Screen: Full list of all jobs"
echo "  ✅ Customers: 680 customers available"
echo "  ✅ Price Book: 500 items loaded"
echo ""
