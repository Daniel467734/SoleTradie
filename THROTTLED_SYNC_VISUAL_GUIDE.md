# Visual Guide: Throttled Cloud Sync Feature

## Where to Find It

### Settings Screen Navigation
```
┌─────────────────────────┐
│   Main App Screen       │
│  [Settings button] ⚙️   │
│                         │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│   Settings Screen       │
│   [Scroll Down]         │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ Cloud Sync & Storage    │
│ ☁️ (Section Header)     │
│                         │
│ [Upload] [Download] ▲   │ ← Regular sync
│                         │
│ ┌─────────────────────┐ │
│ │ 🚀 Throttled Sync   │ │ ← NEW!
│ │ [Start] 42%         │ │
│ └─────────────────────┘ │
│                         │
└─────────────────────────┘
```

## User Flow Diagram

```
User in Settings
       │
       ▼
Sees "Cloud Sync & Storage"
       │
       ▼
Sees new purple "Throttled Sync" box
       │
       ▼
Clicks "Start Throttled Sync" button
       │
       ▼
┌─────────────────────────────────────┐
│  Progress Dialog Appears             │
├─────────────────────────────────────┤
│  🔄 Uploading your local data...    │
│                                      │
│  ████░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │
│  42.5% Complete                      │
│                                      │
│  📝 Syncing: Customers (150 items)  │
│                                      │
│  ℹ️ Throttled to prevent issues     │
│                                      │
│         [Cancel]                     │
└─────────────────────────────────────┘
       │
       ├─→ User waits...
       │
       ▼
   Dialog closes when 100% complete
       │
       ▼
┌─────────────────────────┐
│ ✅ Success Message      │
│                         │
│ Cloud sync completed    │
│ successfully!           │
└─────────────────────────┘
```

## Data Upload Sequence

```
Start Throttled Sync
       │
       ▼
1. Gather Local Data
   ├─ jobs.json (Loaded)
   ├─ customers.json (Loaded)
   ├─ pricebook.json (Loaded)
   ├─ estimates.json (Loaded)
   ├─ invoices.json (Loaded)
   └─ builds.json (Loaded)
       │
       ▼ (Calculate total work)
   Total: 5.2 MB
       │
       ▼
2. Start Upload Sequence
   │
   ├─ Jobs (25 items/batch)
   │  ├─ Batch 1: 📤 (100ms delay)
   │  ├─ Batch 2: 📤 (100ms delay)
   │  └─ ✅ Done (5% complete)
   │
   ├─ Customers (50 items/batch)
   │  ├─ Batch 1: 📤 (100ms delay)
   │  ├─ Batch 2: 📤 (100ms delay)
   │  └─ ✅ Done (25% complete)
   │
   ├─ Price Book (100 items/batch)
   │  ├─ Batch 1: 📤 (100ms delay)
   │  ├─ Batch 2: 📤 (100ms delay)
   │  └─ ✅ Done (60% complete)
   │
   ├─ Estimates: ✅ Done (75%)
   │
   ├─ Invoices: ✅ Done (85%)
   │
   └─ Builds: ✅ Done (100%)
       │
       ▼
3. Sync Complete
   └─ Show Success Message
```

## Progress Bar Animation

```
Starts:     0%
            │░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│

10% (Jobs):    ███░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

30% (Customers): █████████░░░░░░░░░░░░░░░░░░░░░░░░░░

50% (Price):     █████████████░░░░░░░░░░░░░░░░░░░░░

75% (Estimates): ███████████████████░░░░░░░░░░░░░░░

90% (Invoices):  ███████████████████████░░░░░░░░░░░

100% (Builds):   ████████████████████████████████░│ ✅
```

## Progress Dialog Detailed View

```
╔═══════════════════════════════════════════╗
║        One-Way Cloud Sync                 ║
╠═══════════════════════════════════════════╣
║                                            ║
║  Uploading your local data to the cloud..║
║                                            ║
║  ┌────────────────────────────────────┐  ║
║  │████████░░░░░░░░░░░░░░░░░░░░░░░░░│  ║  ← Progress Bar
║  └────────────────────────────────────┘  ║
║                                            ║
║            42.5% Complete                 ║
║                                            ║
║  ┌────────────────────────────────────┐  ║
║  │  📝 Syncing Customers               │  ║  ← Current Task
║  │  Customers (150 items)              │  ║
║  └────────────────────────────────────┘  ║
║                                            ║
║  ┌────────────────────────────────────┐  ║
║  │ ℹ️ Sync is throttled to prevent    │  ║
║  │ network saturation. This ensures   │  ║
║  │ stable uploads even on slow        │  ║
║  │ connections.                       │  ║
║  └────────────────────────────────────┘  ║
║                                            ║
║          [Cancel]                         ║
║                                            ║
╚═══════════════════════════════════════════╝
```

## Settings Card UI

```
┌──────────────────────────────────────────────────┐
│ Cloud Sync & Storage      ☁️ (Header)            │
├──────────────────────────────────────────────────┤
│                                                   │
│ ☁️⬆️  Manual Cloud Sync                           │
│ Upload all local data       [Upload]             │
│                                                   │
│ ─────────────────────────────────────────────── │
│                                                   │
│ ☁️⬇️  Download from Cloud                         │
│ Download latest data        [Download]           │
│                                                   │
│ ═════════════════════════════════════════════════ │  ← Separator
│                                                   │
│ ┌─────────────────────────────────────────────┐ │
│ │ 🚀 Careful One-Way Sync (Throttled)         │ │  ← NEW FEATURE
│ │                                              │ │
│ │ 🎯 Perfect for careful data sync            │ │
│ │ ⏱️  Throttled speed prevents issues         │ │
│ │ 📊 Real-time progress indicator             │ │
│ │                                              │ │
│ │  [Start Throttled Sync]  42%                │ │
│ └─────────────────────────────────────────────┘ │
│                                                   │
│ ℹ️ Sync Status: Ready to sync                    │
│                                                   │
│ All data types sync: customers, price book...   │
│                                                   │
└──────────────────────────────────────────────────┘
```

## Button States

### Default State
```
┌───────────────────────────────────┐
│ Start Throttled Sync              │  ← Clickable
└───────────────────────────────────┘
```

### Active State (Syncing)
```
┌───────────────────────────────────┐
│ ⟳ Syncing... 35%                  │  ← Shows spinner & %
└───────────────────────────────────┘
```

### Disabled State (Already Syncing)
```
┌───────────────────────────────────┐
│ Start Throttled Sync              │  ← Grayed out
└───────────────────────────────────┘
```

## Snackbar Messages

### Success
```
┌────────────────────────────────┐
│ ✅ Cloud sync completed        │
│    successfully!               │
└────────────────────────────────┘
```

### Warning
```
┌────────────────────────────────┐
│ ⚠️  Cloud sync encountered     │
│    issues. Check logs.         │
└────────────────────────────────┘
```

### Error
```
┌────────────────────────────────┐
│ ❌ Cloud sync failed: Connection│
│    timeout. Check internet.    │
└────────────────────────────────┘
```

## Comparison: Before vs After

### Before (No Throttled Sync)
```
Settings Screen
├─ Cloud Sync & Storage
│  ├─ [Upload] [Download]
│  └─ ✅ Status
```

### After (With Throttled Sync)
```
Settings Screen
├─ Cloud Sync & Storage
│  ├─ [Upload] [Download]
│  ├─ ─────────────────────
│  ├─ 🚀 Throttled Sync Section
│  │  ├─ Feature description
│  │  └─ [Start] Button
│  └─ ✅ Status
```

## Mobile Layout

### Phone Portrait
```
┌─────────────────────────┐
│ 🚀 Careful One-Way Sync │
│    (Throttled)          │
├─────────────────────────┤
│ 🎯 Perfect for sync     │
│ ⏱️  Throttled speed     │
│ 📊 Real-time progress   │
│                          │
│  [Start Throttled Sync]  │
│  42%                     │
└─────────────────────────┘
```

### Phone Landscape
```
┌──────────────────────────────────────┐
│ 🚀 Careful One-Way Sync (Throttled)  │
├──────────────────────────────────────┤
│ 🎯 Perfect  ⏱️ Throttled  📊 Progress │
│                                       │
│         [Start Throttled Sync] 42%   │
└──────────────────────────────────────┘
```

---

**Visual Guide Complete** ✅  
All screen layouts and user flows shown above
