import 'package:get_it/get_it.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/local_database.dart';
import '../services/price_book_local_data_source.dart';
import '../services/customer_local_data_source.dart';
import '../services/repository.dart';
import '../services/sync_service_impl.dart';
import '../services/remote_data_source.dart';
import '../services/local_data_source.dart';
import '../models/price_book_item.dart';
import '../models/sync_customer.dart';

final GetIt serviceLocator = GetIt.instance;

Future<void> setupServiceLocator() async {
  // Initialize database
  await LocalDatabase.instance;
  
  // Register data sources
  serviceLocator.registerLazySingleton<PriceBookLocalDataSource>(
    () => PriceBookLocalDataSource(),
  );
  
  serviceLocator.registerLazySingleton<CustomerLocalDataSource>(
    () => CustomerLocalDataSource(),
  );
  
  // For testing: Use local data sources as mock remote data sources
  serviceLocator.registerLazySingleton<LocalDataSource<PriceBookItem>>(
    () => PriceBookLocalDataSource(),
    instanceName: 'PriceBookRemote',
  );
  
  serviceLocator.registerLazySingleton<LocalDataSource<SyncCustomer>>(
    () => CustomerLocalDataSource(),
    instanceName: 'CustomerRemote',
  );
  
  serviceLocator.registerLazySingleton<Connectivity>(
    () => Connectivity(),
  );
  
  // Register SyncService
  serviceLocator.registerLazySingleton<SyncService>(
    () => SyncService(serviceLocator<Connectivity>()),
  );
  
  // serviceLocator.registerLazySingleton<SyncService>(
  //   () => SyncService(serviceLocator<Connectivity>()),
  // );
  
  // Register repositories with mock remote data sources
  serviceLocator.registerLazySingleton<PriceBookRepository>(
    () => PriceBookRepository(
      serviceLocator<PriceBookLocalDataSource>(),
      MockRemoteDataSource<PriceBookItem>(),
      serviceLocator<SyncService>(),
    ),
  );

  serviceLocator.registerLazySingleton<CustomerRepository>(
    () => CustomerRepository(
      serviceLocator<CustomerLocalDataSource>(),
      MockRemoteDataSource<SyncCustomer>(),
      serviceLocator<SyncService>(),
    ),
  );
}

// Mock remote data source for testing
class MockRemoteDataSource<T> implements RemoteDataSource<T> {
  @override
  Future<List<T>> getAll() async {
    print('MockRemoteDataSource: getAll() called');
    return <T>[];
  }

  @override
  Future<T?> getById(String id) async {
    print('MockRemoteDataSource: getById($id) called');
    return null;
  }

  @override
  Future<String> create(T item) async {
    print('MockRemoteDataSource: create() called');
    return 'mock-id-${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<void> update(String id, T item) async {
    print('MockRemoteDataSource: update($id) called');
  }

  @override
  Future<void> delete(String id) async {
    print('MockRemoteDataSource: delete($id) called');
  }

  @override
  Stream<List<T>> watchChanges() {
    print('MockRemoteDataSource: watchChanges() called');
    return Stream.value(<T>[]);
  }
}
