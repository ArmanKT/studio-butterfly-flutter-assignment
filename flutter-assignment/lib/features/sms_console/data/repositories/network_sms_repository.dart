import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../core/exceptions/api_exceptions.dart';
import '../../domain/models/sms_models.dart';
import '../../domain/models/tenant.dart';
import '../../domain/repositories/sms_repository.dart';

class NetworkSmsRepository implements SmsRepository {
  final http.Client _client;
  final String _baseUrl;

  NetworkSmsRepository({
    required http.Client client,
    required String baseUrl,
  })  : _client = client,
        _baseUrl = baseUrl;

  @override
  Future<List<Tenant>> getAvailableTenants() async {
    return const [
      Tenant(
        id: '9f1c2d3e-4a5b-6c7d-8e9f-0a1b2c3d4e5f',
        name: 'Tenant A (Seeded Data)',
        apiKey: 'fw_live_8c21e0b47ad94f13ba77e0c9d51a3b62',
        token: 'mock_token_A',
      ),
      Tenant(
        id: '11111111-2222-3333-4444-555555555555',
        name: 'Tenant B (Empty State)',
        apiKey: 'fw_live_11112222333344445555666677778888',
        token: 'mock_token_B',
      ),
      Tenant(
        id: '99999999-9999-9999-9999-999999999999',
        name: 'Tenant C (Throws 502/Gateway Errors)',
        apiKey: 'fw_live_99999999999999999999999999999999',
        token: 'mock_token_C',
      ),
    ];
  }

  Map<String, String> _headers(String tenantId, String token) {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'X-Tenant-Id': tenantId,
    };
  }

  void _handleError(http.Response response) {
    Map<String, dynamic> errorData = {};
    try {
      if (response.body.isNotEmpty) {
        errorData = jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {
      // Body is not JSON
    }

    final errorCode = errorData['errorCode'] as String?;
    final message = errorData['message'] as String? ?? 'HTTP Error ${response.statusCode}';

    if (response.statusCode == 403) {
      if (errorCode == 'TOKEN_EXPIRED') {
        throw TokenExpiredException(message);
      }
      throw UnauthorizedException(message, statusCode: response.statusCode);
    }

    if (response.statusCode == 429) {
      final retryAfterHeader = response.headers['retry-after'] ?? response.headers['Retry-After'];
      final retryAfter = int.tryParse(retryAfterHeader ?? '5') ?? 5;
      throw RateLimitException(message, retryAfterSeconds: retryAfter, statusCode: response.statusCode);
    }

    if (response.statusCode == 502) {
      throw GatewayException(message, statusCode: response.statusCode);
    }

    if (response.statusCode == 400) {
      throw ValidationException(message, statusCode: response.statusCode, errorCode: errorCode);
    }

    throw ApiException(message, statusCode: response.statusCode, errorCode: errorCode);
  }

  @override
  Future<SmsSendResponse> sendSms({
    required String tenantId,
    required String token,
    required String to,
    required String body,
    String? referenceId,
  }) async {
    final url = Uri.parse('$_baseUrl/api/v1/sms/send');
    final payload = {
      'to': to,
      'body': body,
      if (referenceId != null) 'referenceId': referenceId,
    };

    final response = await _client.post(
      url,
      headers: _headers(tenantId, token),
      body: jsonEncode(payload),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return SmsSendResponse.fromJson(data);
    } else {
      _handleError(response);
      throw UnimplementedError(); // Never reached
    }
  }

  @override
  Future<MessagesPageResponse> getMessages({
    required String tenantId,
    required String token,
    String? cursor,
    int limit = 50,
  }) async {
    final queryParameters = {
      'limit': limit.toString(),
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };

    final url = Uri.parse('$_baseUrl/api/v1/sms/messages').replace(queryParameters: queryParameters);

    final response = await _client.get(
      url,
      headers: _headers(tenantId, token),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return MessagesPageResponse.fromJson(data);
    } else {
      _handleError(response);
      throw UnimplementedError(); // Never reached
    }
  }

  @override
  Future<CostBreakdown> getCostBreakdown({
    required String tenantId,
    required String token,
    required DateTime from,
    required DateTime to,
  }) async {
    final queryParameters = {
      'from': from.toUtc().toIso8601String(),
      'to': to.toUtc().toIso8601String(),
    };

    final url = Uri.parse('$_baseUrl/api/v1/sms/cost/breakdown').replace(queryParameters: queryParameters);

    final response = await _client.get(
      url,
      headers: _headers(tenantId, token),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return CostBreakdown.fromJson(data);
    } else {
      _handleError(response);
      throw UnimplementedError(); // Never reached
    }
  }

  // Token refresh API call (POST /api/v1/auth/refresh)
  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    final url = Uri.parse('$_baseUrl/api/v1/auth/refresh');
    final response = await _client.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refreshToken': refreshToken}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw ApiException('Failed to refresh token', statusCode: response.statusCode);
    }
  }
}
