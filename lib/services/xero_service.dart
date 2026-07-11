import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firestore_service.dart';

class XeroService {
  static const String baseUrl = 'https://api.xero.com/api.xro/2.0';
  static const String authUrl = 'https://login.xero.com/identity/connect/authorize';
  static const String tokenUrl = 'https://identity.xero.com/connect/token';
  static const String connectionsUrl = 'https://api.xero.com/connections';
  // Custom app-scheme redirect so flutter_web_auth_2 can intercept the
  // OAuth callback without needing a real hosted HTTPS endpoint. Must be
  // registered as a URL scheme in Info.plist (iOS) and as an
  // intent-filter in AndroidManifest.xml (Android) - see the
  // ios/Runner/Info.plist and android/app/src/main/AndroidManifest.xml
  // changes documented alongside this service.
  static const String redirectScheme = 'soletradie';
  static const String redirectUri = '$redirectScheme://xero-callback';

  late Dio _dio;

  XeroService() {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
  }

  /// Runs the full Xero OAuth2 Authorization Code flow: opens Xero's
  /// login/consent screen in an in-app browser tab, captures the
  /// redirect back to [redirectUri], exchanges the authorization code
  /// for an access/refresh token pair, discovers the connected
  /// tenant(s) via `/connections`, and persists everything via
  /// [saveTokens]. Returns true on success.
  Future<bool> connect({
    required String clientId,
    required String clientSecret,
  }) async {
    final authorizationUri = Uri.parse(authUrl).replace(queryParameters: {
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'scope': 'accounting.transactions accounting.contacts '
          'accounting.settings offline_access',
    });

    final resultUrl = await FlutterWebAuth2.authenticate(
      url: authorizationUri.toString(),
      callbackUrlScheme: redirectScheme,
    );

    final code = Uri.parse(resultUrl).queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw Exception('Xero authorization was cancelled or returned no code.');
    }

    final tokenResponse = await _dio.post(
      tokenUrl,
      data: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$clientId:$clientSecret'))}',
        },
      ),
    );

    if (tokenResponse.statusCode != 200) {
      throw Exception('Xero token exchange failed: ${tokenResponse.data}');
    }

    final accessToken = tokenResponse.data['access_token'] as String;
    final refreshToken = tokenResponse.data['refresh_token'] as String;

    // Discover which Xero organisation(s) (tenants) this token grants
    // access to, and use the first one - most sole-trader Xero accounts
    // only have a single connected organisation.
    final connectionsResponse = await _dio.get(
      connectionsUrl,
      options: Options(
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      ),
    );

    final connections = List<Map<String, dynamic>>.from(
        connectionsResponse.data ?? const []);
    if (connections.isEmpty) {
      throw Exception(
          'No Xero organisation is connected to this app. Add one in Xero\'s connected apps settings.');
    }

    final tenantId = connections.first['tenantId'] as String;

    await saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      tenantId: tenantId,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('xero_client_id', clientId);
    await prefs.setString('xero_client_secret', clientSecret);

    return true;
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

  /// Voids the given invoice in Xero by InvoiceID. Used to mirror a
  /// local "Void"/"Archive" action so the two ledgers stay in sync
  /// without a Xero invoice being left AUTHORISED/awaiting payment
  /// after the local copy has been archived/deleted.
  ///
  /// Note: Xero only allows voiding invoices that are in DRAFT,
  /// SUBMITTED or AUTHORISED status with no payments applied - if a
  /// payment already exists this call will fail (returns false) and the
  /// invoice should be handled manually in Xero.
  Future<bool> voidInvoice({
    required String accessToken,
    required String xeroInvoiceId,
  }) async {
    try {
      final response = await _dio.post(
        '/Invoices/$xeroInvoiceId',
        data: {
          'Invoices': [
            {
              'InvoiceID': xeroInvoiceId,
              'Status': 'VOIDED',
            }
          ]
        },
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
      print('Failed to void Xero invoice: $e');
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
    // Also mirror the refresh token + tenant to Firestore so the
    // webhook receiver Cloud Function (which runs server-side, with no
    // access to this device's SharedPreferences) can obtain its own
    // access token independently whenever Xero notifies us of a
    // payment. Only the refresh token is stored (access tokens expire
    // in ~30 minutes and are re-derived server-side as needed) alongside
    // the client id/secret so the function can perform its own refresh.
    // Best-effort/fire-and-forget: local Xero sync from this device
    // works regardless of whether this mirror succeeds.
    try {
      final currentUserId = FirestoreService.currentUserId;
      if (currentUserId != null && currentUserId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users/$currentUserId/settings')
            .doc('xero')
            .set({
          'refreshToken': refreshToken,
          'tenantId': tenantId,
          'clientId': prefs.getString('xero_client_id'),
          'clientSecret': prefs.getString('xero_client_secret'),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {
      // Non-fatal - see comment above.
    }
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

  /// Pushes a payment payload to Xero's `/Payments` endpoint, used both
  /// to mark an invoice paid when the user marks it paid in-app, and
  /// (in principle) if we ever need to push a payment Xero doesn't yet
  /// know about. Returns the created payment's raw JSON on success.
  Future<Map<String, dynamic>?> createPayment({
    required String accessToken,
    required Map<String, dynamic> paymentData,
  }) async {
    try {
      final response = await _dio.put(
        '/Payments',
        data: {
          'Payments': [paymentData]
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Xero-tenant-id': await _getStoredTenantId(),
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        final payments =
            List<Map<String, dynamic>>.from(response.data['Payments'] ?? []);
        return payments.isNotEmpty ? payments.first : null;
      }
      return null;
    } catch (e) {
      print('Failed to create Xero payment: $e');
      return null;
    }
  }

  /// Fetches a single invoice by its Xero InvoiceID, used by the webhook
  /// reconciliation flow to check the invoice's current `Status` /
  /// `AmountPaid` before flipping our local `isPaid` flag.
  Future<Map<String, dynamic>?> getInvoiceById({
    required String accessToken,
    required String xeroInvoiceId,
  }) async {
    try {
      final response = await _dio.get(
        '/Invoices/$xeroInvoiceId',
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Xero-tenant-id': await _getStoredTenantId(),
            'Accept': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        final invoices =
            List<Map<String, dynamic>>.from(response.data['Invoices'] ?? []);
        return invoices.isNotEmpty ? invoices.first : null;
      }
      return null;
    } catch (e) {
      print('Failed to fetch Xero invoice by id: $e');
      return null;
    }
  }

  /// Fetches a single invoice by its local `Reference` (our idempotency
  /// key) so we can detect an already-pushed invoice before creating a
  /// new one, even if our local sync-record cache was lost/cleared.
  Future<Map<String, dynamic>?> findInvoiceByReference({
    required String accessToken,
    required String reference,
  }) async {
    try {
      final response = await _dio.get(
        '/Invoices',
        queryParameters: {
          'where': 'Reference=="$reference"',
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
        final invoices =
            List<Map<String, dynamic>>.from(response.data['Invoices'] ?? []);
        return invoices.isNotEmpty ? invoices.first : null;
      }
      return null;
    } catch (e) {
      print('Failed to look up Xero invoice by reference: $e');
      return null;
    }
  }

  /// Fetches the full Chart of Accounts (`/Accounts`), used to populate
  /// the local cache so repeated invoice pushes don't need to re-fetch
  /// account codes every time.
  Future<List<Map<String, dynamic>>> getAllAccounts(
      String accessToken) async {
    try {
      final response = await _dio.get(
        '/Accounts',
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
            response.data['Accounts'] ?? []);
      }
      return [];
    } catch (e) {
      print('Failed to get Xero chart of accounts: $e');
      return [];
    }
  }

  /// Fetches Tax Rates (`/TaxRates`), used to populate the local cache
  /// for tax-type mapping (e.g. NZ/AU 'OUTPUT' GST) without excessive
  /// API calls.
  Future<List<Map<String, dynamic>>> getAllTaxRates(String accessToken) async {
    try {
      final response = await _dio.get(
        '/TaxRates',
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
            response.data['TaxRates'] ?? []);
      }
      return [];
    } catch (e) {
      print('Failed to get Xero tax rates: $e');
      return [];
    }
  }
}
