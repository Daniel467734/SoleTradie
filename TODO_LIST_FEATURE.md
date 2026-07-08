# To-Do List Feature Documentation

## Overview

The To-Do List feature provides a centralized task management system integrated throughout the app. Users can create, manage, and track to-do items with the ability to link them to specific jobs and flexible day schedules.

## Features

### Core Functionality
- **Create To-Do Items**: Add tasks with optional descriptions
- **Checkbox Management**: Mark items as complete/incomplete
- **Edit & Delete**: Modify or remove items with popup menu options
- **Search & Filter**: Find items quickly with real-time search
- **Show/Hide Completed**: Toggle visibility of completed items
- **Item Count**: Total count of items displayed

### Dashboard Integration
- **To-Do List Button**: Added to dashboard with a red badge showing incomplete item count
- **Quick Access**: Navigate directly to the To-Do List screen from the dashboard
- **Auto-Refresh**: Count updates automatically after making changes

### Job Linking
- **Estimate Builder**: "Add to To-Do List" button in app bar links to the current estimate
- **Job Details**: "Add to To-Do List" button in app bar links to the current job
- **Auto-Prefilled**: When opened from these screens, the to-do item is pre-populated with relevant job information

### Flexible Day Jobs
- **Visual Section**: Expandable section showing flexible day jobs for today
- **Amber Highlight**: Clearly distinguishes flexible jobs with amber styling
- **Job Count Badge**: Shows number of flexible jobs available
- **Quick Reference**: Helps users remember which jobs are flexible today

## Architecture

### Data Models

#### `ToDoItem` (`lib/models/todo_item.dart`)
```dart
class ToDoItem {
  final String id;                    // Unique identifier (UUID)
  final String title;                 // Task title
  final String? description;          // Optional description
  bool isCompleted;                   // Completion status
  final DateTime createdDate;         // Creation timestamp
  final String? linkedJobId;          // Optional job reference
  final String? linkedJobTitle;       // Cached job title for display
  DateTime? linkedFlexibleDayId;      // Optional flexible day reference
}
```

### Services

#### `ToDoListService` (`lib/services/todo_list_service.dart`)
Handles all to-do item operations with persistent JSON storage.

**Key Methods:**
- `getAllItems()`: Load all items (cached)
- `addItem()`: Create a new to-do item
- `updateItem()`: Update an existing item
- `toggleItem()`: Toggle completion status
- `deleteItem()`: Remove an item
- `getItemsByJobId()`: Find items linked to a job
- `getFlexibleDayItems()`: Find items linked to a date
- `getIncompleteCount()`: Get count of unfinished items
- `clearCache()`: Force refresh of cached data

**Storage Location:** `{app_documents_dir}/todo_list.json`

**Sorting:** Items are sorted by:
1. Incomplete items first
2. Then by creation date (newest first)

### Screens

#### `ToDoListScreen` (`lib/screens/todo_list_screen.dart`)
Main to-do list interface with the following features:

**Flexible Jobs Section (if available):**
- Expandable section with amber styling
- Shows count badge with number of flexible jobs
- Lists all flexible jobs for today
- Click-through access to view job details

**Search & Filter:**
- Real-time search by item title
- Toggle to show/hide completed items
- Display total count

**Item Management:**
- Checkbox to mark items complete
- Long-press menu for edit/delete
- Visual distinction for completed items (strikethrough)
- Job link display if item is linked to a job

**Add New Item:**
- Floating action button opens bottom sheet
- Title field (required)
- Description field (optional)
- Submits to to-do list service

**Parameters:**
- `prefilledTitle`: Pre-populate title when creating
- `linkedJobId`: Link to specific job ID
- `linkedJobTitle`: Display job title
- `linkedFlexibleDayId`: Link to flexible day date
- `jobs`: List of jobs to display flexible day section

### UI Components

#### Dashboard Button
- Added "To-Do List" button between existing buttons and settings
- Red badge shows incomplete item count
- Badge positioned at top-right of button
- Updates automatically on return from to-do screen

#### App Bar Buttons
- **Estimate Builder**: "Add to To-Do" icon button (add_task)
- **Job Details**: "Add to To-Do" icon button (add_task)

## Integration Points

### Dashboard Screen (`lib/screens/dashboard_screen.dart`)
```dart
// State variable tracks incomplete count
int toDoIncompleteCount = 0;

// Load count on screen appear
Future<void> _loadToDoCount() async {
  final count = await ToDoListService.getIncompleteCount();
  setState(() {
    toDoIncompleteCount = count;
  });
}

// Display button with badge
_DashboardButton(
  icon: Icons.checklist,
  label: 'To-Do List',
  badgeCount: toDoIncompleteCount,
  onTap: () async {
    await Navigator.push(...);
    await _loadToDoCount();
  },
)
```

### Estimate Builder Screen (`lib/screens/estimate_builder_screen.dart`)
```dart
IconButton(
  icon: const Icon(Icons.add_task),
  tooltip: 'Add to To-Do List',
  onPressed: () async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ToDoListScreen(
          prefilledTitle: 'Follow up: ${_customerNameController.text}',
          linkedJobId: widget.job.id,
          linkedJobTitle: '${_customerNameController.text} - Estimate',
        ),
      ),
    );
  },
)
```

### Job Details Screen (`lib/screens/job_details_screen.dart`)
```dart
IconButton(
  icon: const Icon(Icons.add_task),
  tooltip: 'Add to To-Do List',
  onPressed: () async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ToDoListScreen(
          prefilledTitle: 'Follow up: ${job.title}',
          linkedJobId: job.id,
          linkedJobTitle: job.title,
        ),
      ),
    );
  },
)
```

## Usage Examples

### Creating a To-Do from Estimate Builder
1. User opens Estimate Builder for a job
2. User taps "Add to To-Do" button (add_task icon)
3. To-Do screen opens with pre-filled title "Follow up: [Customer Name]"
4. User adds description (optional) and saves
5. Item appears in to-do list linked to the job

### Creating a To-Do from Job Details
1. User opens Job Details
2. User taps "Add to To-Do" button in app bar
3. To-Do screen opens with pre-filled title "Follow up: [Job Name]"
4. User saves item
5. Item appears in to-do list with job link

### Viewing Flexible Day Jobs
1. User opens To-Do List screen
2. If jobs parameter is provided, flexible jobs for today appear at top
3. User can expand/collapse the flexible jobs section
4. Click on any job to see details

### Dashboard Workflow
1. User sees dashboard with red "3" badge on To-Do List button
2. User clicks To-Do List button
3. To-Do List screen opens with 3 incomplete items
4. User completes 2 items
5. Returns to dashboard
6. Badge now shows "1"

## File Structure

```
lib/
├── models/
│   └── todo_item.dart              # ToDoItem data class
├── services/
│   └── todo_list_service.dart      # Service for CRUD operations
└── screens/
    ├── dashboard_screen.dart        # Updated with to-do button
    ├── estimate_builder_screen.dart # Updated with to-do button
    ├── job_details_screen.dart      # Updated with to-do button
    └── todo_list_screen.dart        # Main to-do list UI
```

## Storage

To-do items are persisted to `{app_documents_directory}/todo_list.json` with the following JSON structure:

```json
[
  {
    "id": "uuid-here",
    "title": "Task Title",
    "description": "Optional description",
    "isCompleted": false,
    "createdDate": "2024-01-15T10:30:00.000",
    "linkedJobId": "job-id-123",
    "linkedJobTitle": "Job Title",
    "linkedFlexibleDayId": null
  }
]
```

## Notes

- Items are automatically sorted by completion status and creation date
- The dashboard badge only shows incomplete items
- Job links are informational only - deleting a job doesn't remove linked to-do items
- Flexible day jobs are loaded from the jobs list passed to the screen
- Search is case-insensitive and searches titles only
