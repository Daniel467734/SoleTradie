// Whole-file price book cloud sync via Firebase Storage.
//
// WHY THIS EXISTS: the previous cloud sync approach
// (FirestoreService.batchSavePriceBookItems in firestore_service.dart)
// stored the price book as one Firestore *document per item*. At scale
// (the user reported ~50,000 price book items) this became unreliable:
// - Firestore's batch writes cap at 500 operations, requiring 100 separate
//   batch commits for one sync of 50k items.
// - Reads paginate awkwardly and are slow for "give me the whole list".
// - Real-time listeners (if ever added) would attach 50k document
//   listeners, which is exactly the kind of thing that overwhelms a
//   mobile app.
//
// This service instead uploads/downloads the ENTIRE price book as a
// single JSON file to Firebase Storage (not Firestore). Storage has no
// per-document size limit the way Firestore does (1 MiB/doc), handles
// multi-MB files trivially, and this becomes a single upload + single
// download regardless of whether there are 50 items or 500,000.
//
// Trade-off: this is a "last write wins" whole-file sync, not granular
// per-item sync/merge. That's an intentional simplification per the
// user's request ("just tried as pricebook as a single file with
// everything in it, not individual items"). The local JSON file
// (price_book.json, written by PriceBookService/pricebook_extensive_screen)
// remains the source of truth on-device; this is purely a cloud
// backup/restore mechanism for that same file.

import 'dart:convert';
import 'package:firebase_storage/firebase_storage.dart';
import 'firestore_service.dart';

class PriceBookCloudSyncService {
  /// Storage path for the whole-file price book backup, scoped per user
  /// (mirrors the users/{uid}/... scoping already used by
  /// FirestoreService's Firestore collections).
  static String _storagePathFor(String userId) =>
      'users/$userId/price_book/price_book.json';

  static FirebaseStorage get _storage => FirebaseStorage.instance;

  /// Uploads the entire price book (as a list of raw JSON maps - the
  /// caller is responsible for calling `.toJson()` on each item first,
  /// since this service is deliberately decoupled from any specific
  /// PriceBookItem class definition) as a single file to Firebase
  /// Storage. Overwrites any previous backup.
  ///
  /// Returns true on success. Throws only if not authenticated -
  /// network/Storage errors are left to the caller to catch, since
  /// callers generally want to treat this as best-effort background
  /// sync (see pricebook_extensive_screen.dart's existing pattern of
  /// catching cloud sync errors non-fatally).
  static Future<bool> uploadPriceBook(
    List<Map<String, dynamic>> items, {
    void Function(double progress)? onProgress,
  }) async {
    final userId = FirestoreService.currentUserId;
    if (userId == null) {
      throw Exception('Not authenticated - cannot sync price book to cloud.');
    }

    final payload = jsonEncode({
      'items': items,
      'itemCount': items.length,
      'uploadedAt': DateTime.now().toIso8601String(),
      'version': 1,
    });

    final ref = _storage.ref(_storagePathFor(userId));
    final uploadTask = ref.putString(
      payload,
      format: PutStringFormat.raw,
      metadata: SettableMetadata(contentType: 'application/json'),
    );

    if (onProgress != null) {
      uploadTask.snapshotEvents.listen((snapshot) {
        if (snapshot.totalBytes > 0) {
          onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
        }
      });
    }

    await uploadTask;
    return true;
  }

  /// Downloads the whole-file price book backup and returns the raw
  /// JSON maps (caller converts back to their PriceBookItem type via
  /// `.fromJson()`). Returns an empty list if no backup exists yet
  /// (e.g. first run, never synced) rather than throwing, so callers
  /// can treat "no cloud backup yet" the same as "empty cloud backup".
  static Future<List<Map<String, dynamic>>> downloadPriceBook({
    void Function(double progress)? onProgress,
  }) async {
    final userId = FirestoreService.currentUserId;
    if (userId == null) {
      throw Exception(
          'Not authenticated - cannot restore price book from cloud.');
    }

    final ref = _storage.ref(_storagePathFor(userId));

    try {
      // Check existence + get size first so we can report progress and
      // fail fast with a clear "no backup yet" result instead of an
      // object-not-found exception bubbling up unexpectedly.
      await ref.getMetadata();
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') {
        return [];
      }
      rethrow;
    }

    final downloadTask = ref.getData(50 * 1024 * 1024); // up to 50MB
    final data = await downloadTask;
    if (data == null) return [];

    final decoded = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    final itemsList = decoded['items'] as List<dynamic>? ?? [];
    return itemsList.cast<Map<String, dynamic>>();
  }

  /// Returns metadata about the current cloud backup (item count, when
  /// it was last uploaded) without downloading the full file - useful
  /// for a Settings screen "Last cloud backup: X items, 2 hours ago"
  /// style status display.
  static Future<Map<String, dynamic>?> getBackupInfo() async {
    final userId = FirestoreService.currentUserId;
    if (userId == null) return null;

    final ref = _storage.ref(_storagePathFor(userId));
    try {
      final metadata = await ref.getMetadata();
      return {
        'sizeBytes': metadata.size,
        'updatedAt': metadata.updated?.toIso8601String(),
      };
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return null;
      rethrow;
    }
  }

  /// Deletes the cloud backup entirely (e.g. if the user wants to stop
  /// cloud-syncing the price book, or is troubleshooting).
  static Future<void> deleteBackup() async {
    final userId = FirestoreService.currentUserId;
    if (userId == null) return;

    final ref = _storage.ref(_storagePathFor(userId));
    try {
      await ref.delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }
}
