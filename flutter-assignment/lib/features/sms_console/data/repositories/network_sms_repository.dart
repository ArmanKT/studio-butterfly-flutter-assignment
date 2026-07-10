import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../core/exceptions/api_exceptions.dart';
import '../../domain/models/sms_models.dart';
import '../../domain/repositories/sms_repository.dart';

class NetworkSmsRepository implements SmsRepository {
  final http.Client _client;
  final String _baseUrl;

  NetworkSmsRepository({
    required http.Client client,
    required String baseUrl,
  })  : _client = client,
        _baseUrl = baseUrl;

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
