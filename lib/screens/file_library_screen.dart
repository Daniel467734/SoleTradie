import 'package:flutter/material.dart';
import '../services/demo_mode_service.dart';

/// A simple document/file-template library screen.
///
/// In Demo Mode this browses the in-memory mock file library
/// (`DemoModeService.fileLibrary`) - templates, safety checklists,
/// terms-of-trade docs, etc. Tapping an item opens a mock preview dialog
/// via `DemoModeService.generateCertificatePreview` style logic (fake
/// content, no real file on disk).
///
/// Outside Demo Mode this screen currently has no real backing data
/// source wired up yet (there is no equivalent "file library" concept in
/// the production app), so it shows a friendly empty state.
class FileLibraryScreen extends StatefulWidget {
  const FileLibraryScreen({super.key});

  @override
  State<FileLibraryScreen> createState() => _FileLibraryScreenState();
}

class _FileLibraryScreenState extends State<FileLibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  IconData _iconForCategory(String category) {
    switch (category) {
      case 'Safety':
        return Icons.health_and_safety;
      case 'Legal':
        return Icons.gavel;
      case 'Compliance':
        return Icons.verified_user;
      case 'Templates':
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }

  void _openPreview(String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(name),
        content: const Text(
          '[Demo] This is a mock preview. No real file is opened while in '
          'Demo Mode - this is just a sandboxed placeholder document.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDemo = DemoModeService.instance.isDemoMode;
    final items = isDemo
        ? DemoModeService.instance.searchFileLibrary(_query)
        : [];

    return Scaffold(
      appBar: AppBar(
        title: Text(isDemo ? 'File Library (Demo Mode)' : 'File Library'),
        backgroundColor: isDemo ? Colors.deepPurple : null,
      ),
      body: !isDemo
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  'File Library is currently only available in Demo Mode.\n'
                  'Enable Demo Mode in Settings to explore sample document '
                  'templates, safety checklists, and compliance certificates.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search files',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) => setState(() => _query = val),
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? const Center(child: Text('No files found'))
                      : ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return ListTile(
                              leading: Icon(_iconForCategory(item.category)),
                              title: Text(item.name),
                              subtitle: Text(item.category),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _openPreview(item.name),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
