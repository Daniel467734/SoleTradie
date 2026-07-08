# To-Do List Feature - Setup & Testing Guide

## Quick Start

The To-Do List feature is fully integrated and ready to use. No additional setup required.

## Testing the Feature

### 1. Dashboard Integration
**Expected Behavior:**
- Open the app → Dashboard screen
- Look for "To-Do List" button (3rd row, left side) with checklist icon
- Red badge shows incomplete item count (if any items exist)
- Button sits next to "Settings" button

**Test Steps:**
1. Open dashboard
2. Click "To-Do List" button
3. Verify screen loads properly

### 2. Creating a To-Do from Estimate Builder
**Expected Behavior:**
- Open any job → Tap "Estimate" or create new estimate
- Estimate Builder opens
- App bar has "Add to To-Do" button (add_task icon)
- Title is pre-filled with "Follow up: [Customer Name]"

**Test Steps:**
1. Open dashboard → Click "Estimates/Quotes"
2. Open an existing job estimate or create new estimate
3. In app bar, find "Add to To-Do" button (4th icon from left, looks like checklist)
4. Click it
5. To-Do List screen opens with pre-filled title
6. Add optional description
7. Click "Add Item"
8. Verify item appears in list

### 3. Creating a To-Do from Job Details
**Expected Behavior:**
- Open any job details screen
- App bar shows "Add to To-Do" button as first icon
- Clicking opens To-Do screen with job linked

**Test Steps:**
1. Open dashboard → Click "Jobs"
2. Click on any job to open details
3. In app bar, first icon is "Add to To-Do"
4. Click it
5. To-Do List screen opens with "Follow up: [Job Name]" pre-filled
6. Save the item
7. Verify item shows job link in the list

### 4. To-Do List Features
**Search & Filter:**
1. Add 3-4 items with different names
2. Type in search box - items filter in real-time
3. Check "Show Completed" checkbox - verify only incomplete items show
4. Mark an item complete (click checkbox)
5. Uncheck "Show Completed" - verify completed item hides

**Edit & Delete:**
1. Click the 3-dot menu on any item
2. Select "Edit" - modify title/description and save
3. Click 3-dot menu again
4. Select "Delete" - confirm deletion

**Item Display:**
1. Create item from job detail → verify job link appears
2. Create item without job → verify "No job linked" state

### 5. Flexible Day Jobs Section
**Expected Behavior:**
- If jobs are passed to To-Do screen, flexible jobs for today appear at top
- Section is expandable with amber styling
- Badge shows count of flexible jobs

**Test Steps:**
1. Open "Scheduling" screen from dashboard
2. Find a job marked as "Flexible Day"
3. Navigate to To-Do List via dashboard
4. Look at top of screen - should see expandable "Flexible Day Jobs" section
5. Click to expand - should see list of flexible jobs
6. Count badge should match number of flexible jobs

### 6. Dashboard Badge Update
**Expected Behavior:**
- When returning to dashboard from To-Do screen, badge count updates
- Reflects number of incomplete items

**Test Steps:**
1. Open dashboard, note badge count
2. Click To-Do List
3. Mark an item as complete
4. Go back to dashboard
5. Badge count should decrease by 1

## File Modifications Summary

### New Files Created
- `lib/models/todo_item.dart` - Data model for to-do items
- `lib/services/todo_list_service.dart` - Service layer for CRUD operations
- `lib/screens/todo_list_screen.dart` - Main UI screen

### Files Modified
1. `lib/screens/dashboard_screen.dart`
   - Added import for ToDoListScreen and ToDoListService
   - Added `toDoIncompleteCount` state variable
   - Added `_loadToDoCount()` method
   - Updated `initState()` to load count
   - Updated `_refreshOnReturn()` to reload count
   - Added "To-Do List" button to dashboard grid
   - Updated `_DashboardButton` class to support `badgeCount` parameter

2. `lib/screens/estimate_builder_screen.dart`
   - Added import for ToDoListScreen
   - Added "Add to To-Do" button to app bar actions
   - Button links to To-Do List with pre-filled job context

3. `lib/screens/job_details_screen.dart`
   - Added import for ToDoListScreen
   - Added "Add to To-Do" button as first action in app bar
   - Button links to To-Do List with job context

4. `lib/screens/todo_list_screen.dart`
   - Added flexible jobs parameter to constructor
   - Added `_loadFlexibleJobs()` method
   - Added expandable flexible jobs section at top of list
   - Shows amber-styled expansion tile with job count badge

## Data Storage

To-do items are stored in: `{app_documents_directory}/todo_list.json`

**To View/Debug:**
- Items are stored as JSON array
- Each item includes: id, title, description, isCompleted, createdDate, linkedJobId, linkedJobTitle, linkedFlexibleDayId
- Sorted by: completion status (incomplete first), then creation date (newest first)

## Common Issues & Solutions

### Badge not showing count
- **Cause**: Service not initialized on app start
- **Solution**: Dashboard calls `_loadToDoCount()` in initState

### Items not persisting
- **Cause**: File system access issues
- **Solution**: Check app has file storage permissions (handled by path_provider)

### Flexible jobs not showing
- **Cause**: Jobs list not passed to ToDoListScreen
- **Solution**: Only shows when `jobs` parameter is provided to constructor

### Search not finding items
- **Cause**: Case sensitivity or partial matching
- **Solution**: Search is case-insensitive and searches titles only (not descriptions)

## Feature Highlights

✅ Full CRUD operations (Create, Read, Update, Delete)
✅ Persistent JSON storage
✅ Real-time search & filtering
✅ Completion tracking with checkboxes
✅ Job linking for context
✅ Flexible day job integration
✅ Dashboard badge showing incomplete count
✅ One-click access from estimate and job screens
✅ Auto-prefilled titles for quick entry
✅ Expandable flexible jobs section with count badge

## Next Steps / Enhancements

Potential future improvements:
- Due dates for to-do items
- Priority levels
- Categories/tags
- Recurring tasks
- Export to-do list as PDF
- Email reminders
- Sync with calendar/scheduling
