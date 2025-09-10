# PDF Receipt Templates

This directory contains templates for parsing different PDF receipt formats using AI.

## How to Add a New Template

1. **Create a new class** that extends `PdfReceiptTemplate` in `pdf_receipt_templates.dart`
2. **Implement required methods**:
   - `name`: A short name for your template
   - `description`: A longer description explaining what receipts this template works with
   - `analyzeReceiptText(String text)`: The logic to parse the receipt text

3. **Add your template** to the `PdfReceiptTemplateRegistry._templates` list

## Example Template

```dart
class YourCompanyTemplate extends PdfReceiptTemplate {
  @override
  String get name => 'Your Company';
  
  @override
  String get description => 'Template for Your Company invoices';
  
  @override
  Future<dynamic> analyzeReceiptText(String text) async {
    // Your parsing logic here
    // You can use AI, regex, or any other method to extract:
    // - id_number: Product code/SKU
    // - item_name: Product description
    // - quantity: Quantity purchased
    
    return [
      {"id_number": "12345", "item_name": "Example Item", "quantity": 1}
    ];
  }
}
```

## Available Templates

- **JA Russell**: For JA Russell electrical supplier invoices
  - Extracts: Stock code, item name, quantity, sale price, and purchase price (net price)
  - Uses price book prices if item found by stock code, otherwise uses extracted prices
- **Bunnings**: For Bunnings Warehouse receipts
- **Mitre 10**: For Mitre 10 hardware store receipts
  - Extracts: Item ID, description, quantity, price, and discount percentage
  - Calculates purchase price from sale price minus discount
  - Uses price book prices if item found by Item ID, otherwise uses calculated prices

## Adding to Registry

Add your new template to the registry:

```dart
static final List<PdfReceiptTemplate> _templates = [
  JARussellTemplate(),
  BunningsTemplate(),
  YourCompanyTemplate(), // Add your template here
];
```

## Usage

Templates are automatically available in the estimate builder screen. Users can:

1. Click the receipt icon in the app bar to select a template
2. The selected template will be used for all receipt scanning until changed
3. Different templates can be optimized for different receipt formats

## AI Integration

Templates use OpenAI's API to parse receipt text. You can customize the prompt for each template to work better with specific receipt formats. The AI returns a JSON array with extracted line items.
