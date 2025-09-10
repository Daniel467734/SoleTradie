import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/price_book_item.dart';
import '../models/sync_customer.dart';

abstract class RemoteDataSource<T> {
  Future<List<T>> getAll();
  Future<T?> getById(String id);
  Future<String> create(T item);
  Future<void> update(String id, T item);
  Future<void> delete(String id);
  Stream<List<T>> watchChanges();
}

class PriceBookRemoteDataSource implements RemoteDataSource<PriceBookItem> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'pricebook';

  @override
  Future<List<PriceBookItem>> getAll() async {
    final snapshot = await _firestore.collection(_collection)
        .where('isDeleted', isEqualTo: false)
        .get();
    
    return snapshot.docs.map((doc) => 
        PriceBookItem.fromFirestore(doc.data(), doc.id)).toList();
  }

  @override
  Future<PriceBookItem?> getById(String id) async {
    final doc = await _firestore.collection(_collection).doc(id).get();
    if (doc.exists) {
      return PriceBookItem.fromFirestore(doc.data()!, doc.id);
    }
    return null;
  }

  @override
  Future<String> create(PriceBookItem item) async {
    final docRef = await _firestore.collection(_collection).add(item.toFirestore());
    return docRef.id;
  }

  @override
  Future<void> update(String id, PriceBookItem item) async {
    await _firestore.collection(_collection).doc(id).update(item.toFirestore());
  }

  @override
  Future<void> delete(String id) async {
    await _firestore.collection(_collection).doc(id).update({
      'isDeleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Stream<List<PriceBookItem>> watchChanges() {
    return _firestore.collection(_collection)
        .where('isDeleted', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => 
            PriceBookItem.fromFirestore(doc.data(), doc.id)).toList());
  }
}

class CustomerRemoteDataSource implements RemoteDataSource<SyncCustomer> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'customers';

  @override
  Future<List<SyncCustomer>> getAll() async {
    final snapshot = await _firestore.collection(_collection)
        .where('isDeleted', isEqualTo: false)
        .get();
    
    return snapshot.docs.map((doc) => 
        SyncCustomer.fromFirestore(doc.data(), doc.id)).toList();
  }

  @override
  Future<SyncCustomer?> getById(String id) async {
    final doc = await _firestore.collection(_collection).doc(id).get();
    if (doc.exists) {
      return SyncCustomer.fromFirestore(doc.data()!, doc.id);
    }
    return null;
  }

  @override
  Future<String> create(SyncCustomer item) async {
    final docRef = await _firestore.collection(_collection).add(item.toFirestore());
    return docRef.id;
  }

  @override
  Future<void> update(String id, SyncCustomer item) async {
    await _firestore.collection(_collection).doc(id).update(item.toFirestore());
  }

  @override
  Future<void> delete(String id) async {
    await _firestore.collection(_collection).doc(id).update({
      'isDeleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Stream<List<SyncCustomer>> watchChanges() {
    return _firestore.collection(_collection)
        .where('isDeleted', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => 
            SyncCustomer.fromFirestore(doc.data(), doc.id)).toList());
  }
}
