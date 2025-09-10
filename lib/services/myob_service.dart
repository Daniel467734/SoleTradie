import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MyobService {
  static const String baseUrl = 'https://api.myob.com/accountright';
  late Dio _dio;
  
  MyobService() {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
  }

  Future<bool> testConnection({
    required String apiKey,
    required String companyFileId,
    required String username,
    required String password,
  }) async {
    try {
      // Create basic auth header
      final credentials = base64Encode(utf8.encode('$username:$password'));
      
      final response = await _dio.get(
        '/$companyFileId/GeneralLedger/Account',
        options: Options(
          headers: {
            'Authorization': 'Basic $credentials',
            'x-myobapi-key': apiKey,
            'x-myobapi-version': 'v2',
            'Accept-Encoding': 'gzip,deflate',
            'Content-Type': 'application/json',
          },
        ),
      );
      
      return response.statusCode == 200;
    } catch (e) {
      print('MYOB connection test failed: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getCompanyFiles({
    required String apiKey,
    required String username,
    required String password,
  }) async {
    try {
      final credentials = base64Encode(utf8.encode('$username:$password'));
      
      final response = await _dio.get(
        '',
        options: Options(
          headers: {
            'Authorization': 'Basic $credentials',
            'x-myobapi-key': apiKey,
            'x-myobapi-version': 'v2',
            'Accept-Encoding': 'gzip,deflate',
          },
        ),
      );
      
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      print('Failed to get MYOB company files: $e');
      return [];
    }
  }

  Future<bool> createInvoice({
    required String apiKey,
    required String companyFileId,
    required String username,
    required String password,
    required Map<String, dynamic> invoiceData,
  }) async {
    try {
      final credentials = base64Encode(utf8.encode('$username:$password'));
      
      final response = await _dio.post(
        '/$companyFileId/Sale/Invoice',
        data: invoiceData,
        options: Options(
          headers: {
            'Authorization': 'Basic $credentials',
            'x-myobapi-key': apiKey,
            'x-myobapi-version': 'v2',
            'Accept-Encoding': 'gzip,deflate',
            'Content-Type': 'application/json',
          },
        ),
      );
      
      return response.statusCode == 201;
    } catch (e) {
      print('Failed to create MYOB invoice: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getBankAccounts({
    required String apiKey,
    required String companyFileId,
    required String username,
    required String password,
  }) async {
    try {
      final credentials = base64Encode(utf8.encode('$username:$password'));
      
      final response = await _dio.get(
        '/$companyFileId/GeneralLedger/Account',
        queryParameters: {
          '\$filter': "Classification eq 'Asset' and Type eq 'Bank'",
        },
        options: Options(
          headers: {
            'Authorization': 'Basic $credentials',
            'x-myobapi-key': apiKey,
            'x-myobapi-version': 'v2',
            'Accept-Encoding': 'gzip,deflate',
          },
        ),
      );
      
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data['Items'] ?? []);
      }
      return [];
    } catch (e) {
      print('Failed to get MYOB bank accounts: $e');
      return [];
    }
  }

  Future<bool> syncBankTransactions({
    required String apiKey,
    required String companyFileId,
    required String username,
    required String password,
    required List<Map<String, dynamic>> transactions,
  }) async {
    try {
      final credentials = base64Encode(utf8.encode('$username:$password'));
      bool allSuccess = true;
      
      for (final transaction in transactions) {
        final response = await _dio.post(
          '/$companyFileId/Banking/SpendMoneyTxn',
          data: transaction,
          options: Options(
            headers: {
              'Authorization': 'Basic $credentials',
              'x-myobapi-key': apiKey,
              'x-myobapi-version': 'v2',
              'Accept-Encoding': 'gzip,deflate',
              'Content-Type': 'application/json',
            },
          ),
        );
        
        if (response.statusCode != 201) {
          allSuccess = false;
        }
      }
      
      return allSuccess;
    } catch (e) {
      print('Failed to sync MYOB bank transactions: $e');
      return false;
    }
  }

  static Future<Map<String, String?>> getStoredCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'apiKey': prefs.getString('myob_api_key'),
      'companyFileId': prefs.getString('myob_company_file'),
      'username': prefs.getString('myob_user'),
      'password': prefs.getString('myob_password'),
    };
  }
}
