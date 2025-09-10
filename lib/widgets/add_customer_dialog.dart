import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:convert';

class Customer {
  final String firstName;
  final String lastName;
  final String companyName;
  final String address;
  final String email;
  final String phone;
  final String paymentTerms;

  Customer({
    required this.firstName,
    required this.lastName,
    required this.companyName,
    required this.address,
    required this.email,
    required this.phone,
    required this.paymentTerms,
  });
}

Future<Customer?> showAddCustomerDialog(BuildContext context) async {
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final companyNameController = TextEditingController();
  final addressController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final paymentTermsController = TextEditingController();
  final pasteController = TextEditingController();

  String? errorText;

  void parsePastedText(String text) {
    // Very basic parsing, you can improve this with regex or more logic
    final lines = text.split('\n');
    for (var line in lines) {
      if (line.toLowerCase().contains('name')) {
        firstNameController.text = line.split(':').last.trim();
      } else if (line.toLowerCase().contains('company')) {
        companyNameController.text = line.split(':').last.trim();
      } else if (line.toLowerCase().contains('address')) {
        addressController.text = line.split(':').last.trim();
      } else if (line.toLowerCase().contains('email')) {
        emailController.text = line.split(':').last.trim();
      } else if (line.toLowerCase().contains('phone')) {
        phoneController.text = line.split(':').last.trim();
      } else if (line.toLowerCase().contains('payment')) {
        paymentTermsController.text = line.split(':').last.trim();
      }
    }
  }

  Future<void> importCSV() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final csv = await file.readAsString();
      final rows = const LineSplitter().convert(csv);
      if (rows.length > 1) {
        final headers = rows[0].split(',');
        final values = rows[1].split(',');
        for (int i = 0; i < headers.length; i++) {
          final header = headers[i].trim().toLowerCase();
          final value = values[i].trim();
          if (header == 'first name') firstNameController.text = value;
          if (header == 'last name') lastNameController.text = value;
          if (header == 'company name') companyNameController.text = value;
          if (header == 'address') addressController.text = value;
          if (header == 'email address') emailController.text = value;
          if (header == 'phone number') phoneController.text = value;
          if (header == 'payment terms') paymentTermsController.text = value;
        }
      }
    }
  }

  return showDialog<Customer>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Customer'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: pasteController,
                  decoration: InputDecoration(
                    labelText: 'Paste customer details (optional)',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.paste),
                      onPressed: () {
                        parsePastedText(pasteController.text);
                        setState(() {});
                      },
                    ),
                  ),
                  minLines: 1,
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import from CSV'),
                  onPressed: () async {
                    await importCSV();
                    setState(() {});
                  },
                ),
                const Divider(),
                TextField(
                  controller: firstNameController,
                  decoration: const InputDecoration(labelText: 'First Name'),
                ),
                TextField(
                  controller: lastNameController,
                  decoration: const InputDecoration(labelText: 'Last Name'),
                ),
                TextField(
                  controller: companyNameController,
                  decoration: const InputDecoration(labelText: 'Company Name'),
                ),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'Email Address'),
                  keyboardType: TextInputType.emailAddress,
                ),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: 'Phone Number'),
                  keyboardType: TextInputType.phone,
                ),
                TextField(
                  controller: paymentTermsController,
                  decoration: const InputDecoration(labelText: 'Payment Terms'),
                ),
                if (errorText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(errorText!, style: const TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final first = firstNameController.text.trim();
                final company = companyNameController.text.trim();
                final email = emailController.text.trim();
                final emailValid = RegExp(r"^[\w\.-]+@[\w\.-]+\.\w+$").hasMatch(email);

                if (first.isEmpty && company.isEmpty) {
                  setState(() => errorText = 'First name or Company name is required.');
                  return;
                }
                if (email.isNotEmpty && !emailValid) {
                  setState(() => errorText = 'Please enter a valid email address.');
                  return;
                }
                Navigator.pop(
                  context,
                  Customer(
                    firstName: first,
                    lastName: lastNameController.text.trim(),
                    companyName: company,
                    address: addressController.text.trim(),
                    email: email,
                    phone: phoneController.text.trim(),
                    paymentTerms: paymentTermsController.text.trim(),
                  ),
                );
              },
              child: const Text('Add Customer'),
            ),
          ],
        ),
      );
    },
  );
}