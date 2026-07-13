# 🚀 QUICK START: Delete & Restore Jobs

## Before You Start

1. ✅ **All three code fixes applied and app built**
2. ✅ **Device/emulator connected via ADB**
3. ✅ **92 jobs visible in Firestore console**
4. ✅ **Local backup of jobs.json created**

## Two Commands to Execute

### Command 1: Make Scripts Executable

```bash
chmod +x ~/SOLE\ TRADER\ APP\ VERSIONS/Version\ 2.2/delete_and_restore_jobs.sh
chmod +x ~/SOLE\ TRADER\ APP\ VERSIONS/Version\ 2.2/export_jobs_backup.sh
```

### Command 2: Run Restoration

```bash
zsh ~/SOLE\ TRADER\ APP\ VERSIONS/Version\ 2.2/delete_and_restore_jobs.sh
```

The script will:
1. ✅ Verify device is connected
2. ✅ Backup local jobs.json (just in case)
3. ✅ Delete local jobs.json
4. ✅ Clear app cache
5. ✅ Tell you to manually restart the app

## Manual Steps After Running Script

1. **Close the app** (swipe away or force stop)
2. **Restart the app**
3. **Wait 30-60 seconds** for initial Firestore sync
4. **Watch the logs**:
   ```bash
   adb logcat | grep flutter
   ```
   Look for:
   ```
   ✅ Loaded 92 jobs from Firestore
   ✅ Saved 92 jobs to local storage
   ✅ Synced 92 jobs from Firebase
   ```
5. **Verify jobs appear** in the jobs list

## Expected Outcome

- ✅ App shows ~92 jobs from Firestore
- ✅ Jobs include all invoices/attachments
- ✅ New invoices don't disappear (test by creating one)
- ✅ Cloud sync works smoothly

## If Something Goes Wrong

**Reset to Backup**:
```bash
# Restore from backup
adb push ~/SOLE\ TRADER\ APP\ VERSIONS/Version\ 2.2/backup/jobs_backup_*.json \
         /data/data/com.example.app/app_flutter/jobs.json

# Restart app
adb shell am force-stop com.example.app
adb shell am start com.example.app/com.example.app.MainActivity
```

## Success Indicators 🎉

After restoration, you should see:
- [ ] 91 jobs listed in app
- [ ] Jobs load instantly from local storage
- [ ] Sample jobs show their invoices
- [ ] App syncs with Firestore without errors
- [ ] Can generate new invoices without them disappearing

---

**Ready?** Just run the command above and follow the prompts!

**Questions?** Check `DELETE_AND_RESTORE_JOBS_ACTION_PLAN.md` for detailed info.
