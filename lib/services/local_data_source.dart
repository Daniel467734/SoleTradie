abstract class LocalDataSource<T> {
  Future<List<T>> getAll();
  Future<T?> getById(String id);
  Future<List<T>> search(String query);
  Future<void> insert(T item);
  Future<void> update(T item);
  Future<void> delete(String id);
  Future<List<T>> getPendingSync();
  Future<void> markSynced(String id, String cloudId);
}
