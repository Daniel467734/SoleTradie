import 'package:flutter/material.dart';
import '../models/sync_customer.dart';
import '../services/repository.dart';

class CustomerOfflineWidget extends StatefulWidget {
  final SyncCustomer customer;
  final CustomerRepository repository;

  const CustomerOfflineWidget({
    super.key,
    required this.customer,
    required this.repository,
  });

  @override
  State<CustomerOfflineWidget> createState() => _CustomerOfflineWidgetState();
}

class _CustomerOfflineWidgetState extends State<CustomerOfflineWidget> {
  bool _isRemote = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _isRemote = widget.customer.isRemote;
  }

  Future<void> _toggleRemote() async {
    setState(() {
      _isSyncing = true;
    });

    try {
      await widget.repository.setRemote(widget.customer.customerId, !_isRemote);
      
      if (!_isRemote) {
        // When enabling remote, trigger a sync to download all related data
        await widget.repository.sync();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Customer made available offline. All related data will be cached.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Customer removed from offline mode.'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      setState(() {
        _isRemote = !_isRemote;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isSyncing = false;
      });
    }
  }

  Future<void> _syncNow() async {
    setState(() {
      _isSyncing = true;
    });

    try {
      await widget.repository.sync();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sync completed successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isSyncing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isRemote ? Icons.offline_pin : Icons.cloud_outlined,
                  color: _isRemote ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isRemote ? 'Available Offline' : 'Online Only',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (_isSyncing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _isRemote
                  ? 'All data for this customer is cached locally and will sync when connected.'
                  : 'Customer data requires internet connection to access.',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isSyncing ? null : _toggleRemote,
                    icon: Icon(_isRemote ? Icons.cloud_off : Icons.offline_pin),
                    label: Text(_isRemote ? 'Remove from Offline' : 'Make Available Offline'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isRemote ? Colors.orange : Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isSyncing ? null : _syncNow,
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
