import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:shared_preferences/shared_preferences.dart';

class XeroService {
  static const String baseUrl = 'https://api.xero.com/api.xro/2.0';
  static const String authUrl = 'https://login.xero.com/identity/connect/authorize';
  static const String tokenUrl = 'https://identity.xero.com/connect/token';
  static const String redirectUri = 'https://localhost:8080/callback';
  
  late Dio _dio;
  
  XeroService() {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
  }

  Future<oauth2.Client> createOAuthClient({
    required String clientId,
    required String clientSecret,
  }) async {
    final grant = oauth2.AuthorizationCodeGrant(
      clientId,
      Uri.parse(authUrl),
      Uri.parse(tokenUrl),
      secret: clientSecret,
    );

    final authorizationUrl = grant.getAuthorizationUrl(
      Uri.parse(redirectUri),
      scopes: [
        'accounting.transactions',
        'accounting.contacts',
        'accounting.settings',
        'offline_access'
      ],
    );

    // In a real implementation, you would open this URL in a browser
    // and handle the callback to extract the authorization code
    print('Open this URL in browser: $authorizationUrl');
    
    // For now, we'll simulate the OAuth flow
    // In production, implement proper OAuth callback handling
    throw UnimplementedError('OAuth flow needs to be implemented with proper browser handling');
  }

  Future<bool> testConnection(String accessToken) async {
    try {
      final response = await _dio.get(
        '/Organisation',
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Xero-tenant-id': await _getStoredTenantId(),
            'Accept': 'application/json',
          },
        ),
      );
      
      return response.statusCode == 200;
    } catch (e) {
      print('Xero connection test failed: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getBankAccounts(String accessToken) async {
    try {
      final response = await _dio.get(
        '/Accounts',
        queryParameters: {
          'where': 'Type=="BANK"',
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Xero-tenant-id': await _getStoredTenantId(),
            'Accept': 'application/json',
          },
        ),
      );
      
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(
          response.data['Accounts'] ?? []
        );
      }
      return [];
    } catch (e) {
      print('Failed to get Xero bank accounts: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getBankTransactions({
    required String accessToken,
    required String accountId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      Map<String, dynamic> queryParams = {};
      
      if (fromDate != null || toDate != null) {
        String whereClause = '';
        if (fromDate != null) {
          whereClause += 'Date >= DateTime(${fromDate.year}, ${fromDate.month}, ${fromDate.day})';
        }
        if (toDate != null) {
          if (whereClause.isNotEmpty) whereClause += ' AND ';
          whereClause += 'Date <= DateTime(${toDate.year}, ${toDate.month}, ${toDate.day})';
        }
        queryParams['where'] = whereClause;
      }
      
      final response = await _dio.get(
        '/BankTransactions',
        queryParameters: queryParams,
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Xero-tenant-id': await _getStoredTenantId(),
            'Accept': 'application/json',
          },
        ),
      );
      
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(
          response.data['BankTransactions'] ?? []
        );
      }
      return [];
    } catch (e) {
      print('Failed to get Xero bank transactions: $e');
      return [];
    }
  }

  Future<bool> createInvoice({
    required String accessToken,
    required Map<String, dynamic> invoiceData,
  }) async {
    try {
      final response = await _dio.put(
        '/Invoices',
        data: {'Invoices': [invoiceData]},
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Xero-tenant-id': await _getStoredTenantId(),
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      );
      
      return response.statusCode == 200;
    } catch (e) {
      print('Failed to create Xero invoice: $e');
      return false;
    }
  }

  Future<bool> createContact({
    required String accessToken,
    required Map<String, dynamic> contactData,
  }) async {
    try {
      final response = await _dio.put(
        '/Contacts',
        data: {'Contacts': [contactData]},
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Xero-tenant-id': await _getStoredTenantId(),
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      );
      
      return response.statusCode == 200;
    } catch (e) {
      print('Failed to create Xero contact: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> syncBankFeeds({
    required String accessToken,
    required List<String> accountIds,
  }) async {
    List<Map<String, dynamic>> allTransactions = [];
    
    for (String accountId in accountIds) {
      final transactions = await getBankTransactions(
        accessToken: accessToken,
        accountId: accountId,
        fromDate: DateTime.now().subtract(const Duration(days: 30)),
        toDate: DateTime.now(),
      );
      allTransactions.addAll(transactions);
    }
    
    return allTransactions;
  }

  Future<String?> _getStoredTenantId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('xero_tenant_id');
  }

  static Future<Map<String, String?>> getStoredCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'clientId': prefs.getString('xero_client_id'),
      'clientSecret': prefs.getString('xero_client_secret'),
      'accessToken': prefs.getString('xero_access_token'),
      'refreshToken': prefs.getString('xero_refresh_token'),
      'tenantId': prefs.getString('xero_tenant_id'),
    };
  }

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required String tenantId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('xero_access_token', accessToken);
    await prefs.setString('xero_refresh_token', refreshToken);
    await prefs.setString('xero_tenant_id', tenantId);
  }

  Future<bool> refreshAccessToken() async {
    final credentials = await getStoredCredentials();
    final refreshToken = credentials['refreshToken'];
    final clientId = credentials['clientId'];
    final clientSecret = credentials['clientSecret'];
    
    if (refreshToken == null || clientId == null || clientSecret == null) {
      return false;
    }
    
    try {
      final response = await _dio.post(
        tokenUrl,
        data: {
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
        },
        options: Options(
          headers: {
            'Authorization': 'Basic ${base64Encode(utf8.encode('$clientId:$clientSecret'))}',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        ),
      );
      
      if (response.statusCode == 200) {
        final data = response.data;
        await saveTokens(
          accessToken: data['access_token'],
          refreshToken: data['refresh_token'] ?? refreshToken,
          tenantId: credentials['tenantId']!,
        );
        return true;
      }
      return false;
    } catch (e) {
      print('Failed to refresh Xero token: $e');
      return false;
    }
  }
}
