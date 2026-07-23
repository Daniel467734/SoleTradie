# Quick Reference: Throttled Cloud Sync

## Where to Find It
**Settings** → Scroll down to **"Cloud Sync & Storage"** section

You'll see a new **purple box** labeled **"Careful One-Way Sync (Throttled)"**

## What It Does
Slowly uploads all your app data to the cloud with real-time progress tracking.

**Data uploaded:**
- 📋 Jobs (all estimates & invoices for jobs)
- 👥 Customers (contact information)
- 💰 Price Book (item pricing database)
- 📄 Estimates (draft quotes)
- 🧾 Invoices (billing records)
- 🏗️ In-Progress Builds (unsaved estimates)

## How to Use

1. **Click "Start Throttled Sync"** button
2. **Watch the progress dialog** showing:
   - Purple progress bar fills from left to right
   - Percentage (0% → 100%)
   - What's currently uploading
3. **Wait for completion** - dialog closes automatically
4. **See success message** - green snackbar confirms upload worked

## Key Features

✨ **Throttled** - 500ms delay prevents network overload  
📊 **Progress tracking** - See exactly what percentage is done  
📝 **Operation details** - Know which data type is uploading  
🛡️ **Error resilient** - Continues if one batch fails  
⏸️ **Cancellable** - Click Cancel button to stop

## Why Use This Instead of Regular Sync?

| Feature | Regular Sync | Throttled Sync |
|---------|--------------|----------------|
| Speed | Fast | Slower but steady |
| Network safety | Can overload | Safe on slow connections |
| Progress visibility | None | Full real-time progress |
| Operation details | Hidden | Shows what's syncing |
| Works offline | No | No (needs internet) |
| For large datasets | Risky | Perfect |

## Common Questions

**Q: How long does it take?**  
A: Depends on data size. Small ~10 seconds, Medium ~1-2 min, Large (1000+ items) ~5-10 min

**Q: Can I cancel mid-sync?**  
A: Yes, click the Cancel button in the dialog. Already uploaded data stays on cloud.

**Q: What if my connection drops?**  
A: Sync stops. You can restart and it will re-upload. No data is lost.

**Q: Does it upload everything?**  
A: Yes - all jobs, customers, price book, estimates, invoices. Everything gets uploaded.

**Q: Is this a backup?**  
A: No, it's just an upload. Your local data stays unchanged. Use backup feature separately if needed.

**Q: Can I use this on mobile?**  
A: Yes! Works on both iOS and Android.

---

**💡 Pro Tip**: Use this before major app updates or after importing large amounts of data to ensure everything is safely backed up to the cloud.
