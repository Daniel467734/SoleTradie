import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/price_book_item.dart';
import '../models/sync_customer.dart';
import '../models/sync_outbox.dart';

class LocalDatabase {
  static Isar? _isar;
  
  static Future<Isar> get instance async {
    if (_isar != null) return _isar!;
    
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [
        PriceBookItemSchema,
        SyncCustomerSchema,
        SyncOutboxSchema,
      ],
      directory: dir.path,
    );
    print('LocalDatabase: Isar database opened successfully');
    
    return _isar!;
  }
  
  static Future<void> close() async {
    await _isar?.close();
    _isar = null;
    print('LocalDatabase: Isar database closed');
  }
}
