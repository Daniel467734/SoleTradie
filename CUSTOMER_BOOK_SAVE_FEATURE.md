# Customer Book Save Feature - Job Details Screen

## Overview
Added a **"Save to Customers"** feature in the Customer Details dialog of Job Details screen. This allows users to save customer information for reuse across jobs, with options to create a new customer or overwrite an existing one.

## Feature Details

### 1. **Save as New Customer**
- Captures all entered customer details (name, company, address, email, body corporate number)
- Creates a new unique customer record in the customer book
- Automatically generates a unique ID using timestamp
- Shows success confirmation via snackbar

**Usage Flow:**
1. Open Job Details
2. Edit Customer Details
3. Enter/modify customer information
4. Click "New Customer" button
5. Customer saved to customer book ✅

### 2. **Overwrite Existing Customer**
- Open a searchable dialog to find an existing customer
- Allows search by: name, company name, or email
- Shows double confirmation before overwriting
- Updates the selected customer with new details

**Usage Flow:**
1. Open Job Details
2. Edit Customer Details
3. Enter/modify customer information
4. Click "Overwrite" button
5. Search and select customer to update
6. Confirm the overwrite
7. Customer record updated ✅

### 3. **Customer Search Dialog**
- Searchable list of all customers
- Real-time filtering as user types
- Visual indication of selected customer
- Select/Cancel actions

## Technical Implementation

### New Methods Added

#### `_saveCustomerNew(String name, String companyName, String bodyCorporateNumber, String address, String email)`
- Validates that customer name is not empty
- Generates unique customer ID
- Creates new Customer object with all provided details
- Saves via `FirebaseIntegrationService.saveCustomer()`
- Shows success/error feedback

**Example Code:**
```dart
final customerId = 'customer_${DateTime.now().millisecondsSinceEpoch}';
final newCustomer = Customer(
  id: customerId,
  name: trimmedName,
  companyName: companyName.trim(),
  address: address.trim(),
  email: email.trim(),
  phone: '', // Optional
  bodyCorporateNumber: bodyCorporateNumber.trim(),
);
await FirebaseIntegrationService.saveCustomer(newCustomer);
```

#### `_overwriteExistingCustomer(String name, ..., String email)`
- Loads all existing customers from customer book
- Shows customer search dialog if customers exist
- Displays double-confirmation dialog showing:
  - Customer being updated
  - New details to be saved
  - Warning message in red
- Uses `copyWith()` to preserve existing customer fields
- Saves updated customer via `FirebaseIntegrationService`

#### `_showCustomerSearchDialog(List<Customer> customers)`
- Displays searchable dialog with customer list
- Filters by: name, company name, or email (case-insensitive)
- Highlights selected customer with blue background
- Returns selected customer or null if cancelled
- Displays "No matches" message when search yields no results

### UI Components

**Save to Customers Section** (in Customer Details Dialog):
```
┌─ Save to Customers: ─────────────────┐
│ [+ New Customer] [✏️  Overwrite]    │
└──────────────────────────────────────┘
```

**Search Dialog**:
```
┌─ Select Customer to Overwrite ────┐
│ [Search by name, company, email] │
│ ┌──────────────────────────────┐ │
│ │ ○ Unity Books                │ │
│ │   Unity Publishing           │ │
│ │   unity@books.co.nz          │ │
│ │                              │ │
│ │ ○ Acme Corp (selected)       │ │
│ │   Acme Corporation           │ │
│ │   admin@acme.com             │ │
│ └──────────────────────────────┘ │
│ [Cancel] [Select]                │
└──────────────────────────────────┘
```

**Confirmation Dialog**:
```
┌─ Confirm Overwrite ────────────────┐
│ This will update the customer:     │
│                                    │
│ "Acme Corp"                        │
│                                    │
│ New details:                       │
│ Name: New Company Name             │
│ Company: New Company Ltd           │
│ Address: 123 New Street            │
│ Email: new@company.com             │
│                                    │
│ ⚠️ Are you sure you want to       │
│ overwrite this customer?           │
│                                    │
│ [Cancel] [Yes, Overwrite]         │
└──────────────────────────────────┘
```

## Error Handling

- **Empty customer name**: Shows error snackbar, prevents save
- **No customers to overwrite**: Shows informational message directing to "New Customer"
- **Save failures**: Catches exceptions and shows error snackbar with details
- **Network/Firebase issues**: Handled by `FirebaseIntegrationService`

## User Feedback

All operations show snackbar notifications:
- ✅ "Customer 'Name' saved to customer book"
- ✅ "Customer 'Name' updated successfully"  
- ❌ "Failed to save customer: [error details]"
- ⚠️ "Customer name is required"
- ⚠️ "No customers in customer book yet. Use 'New Customer' instead."

## Integration Points

### Dependencies
- `FirebaseIntegrationService.saveCustomer()` - Persist customer to local/cloud
- `FirebaseIntegrationService.loadCustomers()` - Fetch existing customers
- `Customer` model - Represents customer data
- `showDialog()` - Flutter UI for dialogs

### Import Added
```dart
import '../models/customer.dart';
```

## Benefits

| Benefit | Impact |
|---------|--------|
| **Reusable Customers** | No need to re-enter customer info for recurring jobs |
| **Quick Lookup** | Search existing customers by name, company, or email |
| **Data Consistency** | Updates flow to customer book for centralized management |
| **Error Prevention** | Double confirmation prevents accidental overwrites |
| **User-Friendly** | Clear feedback and visual cues throughout the process |

## Testing Checklist

- [ ] Click "New Customer" → Creates new customer in book
- [ ] Search existing customer by name → Filters correctly
- [ ] Search existing customer by company → Filters correctly
- [ ] Search existing customer by email → Filters correctly
- [ ] Click "Select" without choosing → Disables/does nothing
- [ ] Click "Cancel" on search → Returns to edit dialog
- [ ] Confirm overwrite → Updates customer details
- [ ] Cancel confirm → No changes made
- [ ] Empty customer name → Shows error, no save
- [ ] Network offline → Appropriate error shown
- [ ] Verify customer book updated by opening Customers screen

## Related Files
- `job_details_screen.dart` - Contains the Customer Details editor with save feature
- `firebase_integration_service.dart` - Handles customer persistence
- `customers_screen.dart` - Displays customer book
- `models/customer.dart` - Customer data model
