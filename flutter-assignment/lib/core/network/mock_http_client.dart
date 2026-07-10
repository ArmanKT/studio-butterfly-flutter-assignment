import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// Global controller to configure simulated behavior in the Mock HTTP client.
class MockApiSettings {
  static Duration networkDelay = const Duration(milliseconds: 300);
  static bool force502Error = false;
  static bool force429Error = false;
  static int rateLimitRetryAfterSeconds = 5;

  static void reset() {
    networkDelay = const Duration(milliseconds: 300);
    force502Error = false;
    force429Error = false;
    rateLimitRetryAfterSeconds = 5;
  }
}

/// An intercepting [http.Client] that simulates the entire Formwork SMS API contract.
/// Runs entirely in memory, validating headers, token lifecycle, pagination,
/// and precise decimal calculations in minor units.
class MockHttpClient extends http.BaseClient {
  final Map<String, List<Map<String, dynamic>>> _tenantMessages = {};
  static const _uuid = Uuid();

  MockHttpClient() {
    _seedInitialData();
  }

  // Pre-seed some history for testing pagination and layout
  void _seedInitialData() {
    const tenantA = '9f1c2d3e-4a5b-6c7d-8e9f-0a1b2c3d4e5f'; // Seeding 65 messages to test pagination
    final messages = <Map<String, dynamic>>[];
    final now = DateTime.now().toUtc();

    for (int i = 1; i <= 65; i++) {
      final isEven = i % 2 == 0;
      final provider = isEven ? 'TWILIO' : 'AWS_SNS';
      final cost = isEven ? '0.0750' : '0.0460';
      final sentAt = now.subtract(Duration(minutes: i * 15));
      final recipient = '+4915${i.toString().padLeft(5, '0')}78';

      final maskedRecipient = '${recipient.substring(0, 6)}*****${recipient.substring(recipient.length - 2)}';

      messages.add({
        'messageId': 'SM${_uuid.v4().substring(0, 8)}',
        'recipient': maskedRecipient,
        'status': 'DELIVERED',
        'segmentCount': 1,
        'cost': cost,
        'sentAt': sentAt.toIso8601String(),
        'provider': provider, // Used for cost breakdown mapping
      });
    }
    _tenantMessages[tenantA] = messages;

    // Tenant B ('11111111-2222-3333-4444-555555555555') remains empty to test the Empty State UI.
    _tenantMessages['11111111-2222-3333-4444-555555555555'] = [];
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // 1. Simulate network latency
    if (MockApiSettings.networkDelay.inMilliseconds > 0) {
      await Future.delayed(MockApiSettings.networkDelay);
    }

    final path = request.url.path;
    final method = request.method;

    // Route: Authentication refresh is public
    if (path == '/api/v1/auth/refresh' && method == 'POST') {
      return _handleTokenRefresh(request);
    }

    // 2. Validate multi-tenancy and authorization headers
    final tenantId = request.headers['X-Tenant-Id'];
    final auth = request.headers['Authorization'];

    if (tenantId == null || tenantId.isEmpty) {
      return _jsonResponse(
        403,
        {'errorCode': 'FORBIDDEN', 'message': 'Missing X-Tenant-Id header'},
      );
    }

    if (auth == null || !auth.startsWith('Bearer ')) {
      return _jsonResponse(
        403,
        {'errorCode': 'UNAUTHORIZED', 'message': 'Invalid or missing Authorization header'},
      );
    }

    final token = auth.replaceFirst('Bearer ', '');
    if (token == 'expired_token') {
      return _jsonResponse(
        403,
        {'errorCode': 'TOKEN_EXPIRED', 'message': 'Token has expired'},
      );
    }

    // Tenant-specific errors (for Tenant C/Errors)
    if (tenantId == '99999999-9999-9999-9999-999999999999') {
      return _jsonResponse(
        502,
        {'errorCode': 'BAD_GATEWAY', 'message': 'Upstream connection failed'},
      );
    }

    // Global settings injection
    if (MockApiSettings.force502Error) {
      return _jsonResponse(
        502,
        {'errorCode': 'BAD_GATEWAY', 'message': 'Provider gateway error (forced)'},
      );
    }

    // Router
    try {
      if (path == '/api/v1/sms/send' && method == 'POST') {
        if (MockApiSettings.force429Error) {
          return _jsonResponse(
            429,
            {'errorCode': 'RATE_LIMIT', 'message': 'Too many requests. Cooldown active.'},
            headers: {'retry-after': MockApiSettings.rateLimitRetryAfterSeconds.toString()},
          );
        }
        return await _handleSendSms(request, tenantId);
      } else if (path == '/api/v1/sms/messages' && method == 'GET') {
        return _handleGetMessages(request, tenantId);
      } else if (path == '/api/v1/sms/cost/breakdown' && method == 'GET') {
        return _handleGetCostBreakdown(request, tenantId);
      }
    } catch (e) {
      return _jsonResponse(
        500,
        {'errorCode': 'INTERNAL_ERROR', 'message': e.toString()},
      );
    }

    return _jsonResponse(
      404,
      {'errorCode': 'NOT_FOUND', 'message': 'Resource not found'},
    );
  }

  // POST /api/v1/auth/refresh
  Future<http.StreamedResponse> _handleTokenRefresh(http.BaseRequest request) async {
    final bodyStr = await _readRequestBody(request);
    final body = jsonDecode(bodyStr) as Map<String, dynamic>;
    final refreshToken = body['refreshToken'];

    if (refreshToken == null || refreshToken.toString().isEmpty) {
      return _jsonResponse(400, {'errorCode': 'BAD_REQUEST', 'message': 'Missing refreshToken'});
    }

    return _jsonResponse(200, {
      'accessToken': 'refreshed_token_${DateTime.now().millisecondsSinceEpoch}',
      'expiresIn': 900,
    });
  }

  // POST /api/v1/sms/send
  Future<http.StreamedResponse> _handleSendSms(http.BaseRequest request, String tenantId) async {
    final bodyStr = await _readRequestBody(request);
    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(bodyStr) as Map<String, dynamic>;
    } catch (_) {
      return _jsonResponse(400, {'errorCode': 'BAD_REQUEST', 'message': 'Malformed JSON'});
    }

    final to = payload['to'] as String?;
    final body = payload['body'] as String?;

    if (to == null || body == null) {
      return _jsonResponse(400, {'errorCode': 'BAD_REQUEST', 'message': 'to and body are required'});
    }

    // Phone E.164 check (rough regex: + followed by 7-15 digits)
    final phoneRegex = RegExp(r'^\+[1-9]\d{6,14}$');
    if (!phoneRegex.hasMatch(to)) {
      return _jsonResponse(400, {
        'errorCode': 'INVALID_PHONE_NUMBER',
        'message': 'must be E.164',
      });
    }

    // SMS segments calculation (160 char limit for basic GSM)
    final segments = (body.length / 160).ceil();

    // Round-robin selection of provider
    final index = (_tenantMessages[tenantId]?.length ?? 0) + 1;
    final String provider;
    final int rateMicroCents;
    if (index % 3 == 0) {
      provider = 'TWILIO';
      rateMicroCents = 750; // 0.0750
    } else if (index % 3 == 1) {
      provider = 'AWS_SNS';
      rateMicroCents = 460; // 0.0460
    } else {
      provider = 'VONAGE';
      rateMicroCents = 650; // 0.0650
    }

    final costVal = rateMicroCents * segments;
    final costStr = (costVal / 10000).toStringAsFixed(4);
    final messageId = 'SM${_uuid.v4().substring(0, 8)}';

    final String maskedPhone;
    if (to.length > 8) {
      maskedPhone = '${to.substring(0, 5)}*****${to.substring(to.length - 2)}';
    } else {
      maskedPhone = '${to.substring(0, 2)}***${to.substring(to.length - 1)}';
    }

    // Store raw record in database
    final record = {
      'messageId': messageId,
      'recipient': maskedPhone,
      'status': 'ACCEPTED',
      'segmentCount': segments,
      'cost': costStr,
      'sentAt': DateTime.now().toUtc().toIso8601String(),
      'provider': provider,
    };

    _tenantMessages.putIfAbsent(tenantId, () => []).add(record);

    // Asynchronously transition the delivery status (ACCEPTED -> SENT -> DELIVERED)
    _startStatusTransition(tenantId, messageId);

    return _jsonResponse(202, {
      'messageId': messageId,
      'provider': provider,
      'status': 'ACCEPTED',
      'segmentCount': segments,
      'cost': costStr,
      'currency': 'EUR',
    });
  }

  // GET /api/v1/sms/messages?cursor=<opaque>&limit=50
  http.StreamedResponse _handleGetMessages(http.BaseRequest request, String tenantId) {
    final uri = request.url;
    final limit = int.tryParse(uri.queryParameters['limit'] ?? '50') ?? 50;
    final cursorStr = uri.queryParameters['cursor'];

    final allMessages = List<Map<String, dynamic>>.from(_tenantMessages[tenantId] ?? []);
    // Sort descending by sentAt so latest messages appear first
    allMessages.sort((a, b) => b['sentAt'].compareTo(a['sentAt']));

    int offset = 0;
    if (cursorStr != null && cursorStr.isNotEmpty) {
      try {
        final decoded = utf8.decode(base64.decode(cursorStr));
        final parsed = jsonDecode(decoded) as Map<String, dynamic>;
        offset = parsed['offset'] as int;
      } catch (_) {
        return _jsonResponse(400, {'errorCode': 'INVALID_CURSOR', 'message': 'Could not parse cursor'});
      }
    }

    final pageItems = allMessages.skip(offset).take(limit).toList();
    final hasMore = offset + limit < allMessages.length;
    String? nextCursor;
    if (hasMore) {
      nextCursor = base64.encode(utf8.encode(jsonEncode({'offset': offset + limit})));
    }

    return _jsonResponse(200, {
      'items': pageItems,
      'nextCursor': nextCursor,
    });
  }

  // GET /api/v1/sms/cost/breakdown?from=<iso8601>&to=<iso8601>
  http.StreamedResponse _handleGetCostBreakdown(http.BaseRequest request, String tenantId) {
    final uri = request.url;
    final fromStr = uri.queryParameters['from'];
    final toStr = uri.queryParameters['to'];

    if (fromStr == null || toStr == null) {
      return _jsonResponse(400, {
        'errorCode': 'BAD_REQUEST',
        'message': 'from and to date ranges are required query parameters'
      });
    }

    final from = DateTime.parse(fromStr);
    final to = DateTime.parse(toStr);

    final allMessages = _tenantMessages[tenantId] ?? [];
    int totalCostMicroCents = 0;
    final providerCosts = <String, int>{};
    final providerCounts = <String, int>{};

    for (final msg in allMessages) {
      final sentAt = DateTime.parse(msg['sentAt'] as String);
      if (sentAt.isAfter(from) && sentAt.isBefore(to)) {
        // Parse the cost decimal string into integer micro-cents
        final parts = (msg['cost'] as String).split('.');
        final whole = int.parse(parts[0]);
        final fraction = int.parse(parts[1].padRight(4, '0').substring(0, 4));
        final costMicroCents = whole * 10000 + fraction;

        final provider = msg['provider'] as String;

        totalCostMicroCents += costMicroCents;
        providerCosts[provider] = (providerCosts[provider] ?? 0) + costMicroCents;
        providerCounts[provider] = (providerCounts[provider] ?? 0) + 1;
      }
    }

    final rows = providerCosts.entries.map((entry) {
      final costStr = (entry.value / 10000).toStringAsFixed(4);
      return {
        'provider': entry.key,
        'totalCost': costStr,
        'messageCount': providerCounts[entry.key] ?? 0,
      };
    }).toList();

    final totalCostStr = (totalCostMicroCents / 10000).toStringAsFixed(4);

    return _jsonResponse(200, {
      'currency': 'EUR',
      'totalCost': totalCostStr,
      'rows': rows,
    });
  }

  // Asynchronous simulation of delivery state machine
  void _startStatusTransition(String tenantId, String messageId) {
    // Transition to SENT after 2 seconds
    Timer(const Duration(seconds: 2), () {
      final list = _tenantMessages[tenantId];
      if (list != null) {
        final idx = list.indexWhere((m) => m['messageId'] == messageId);
        if (idx != -1) {
          list[idx]['status'] = 'SENT';
        }
      }

      // Transition to DELIVERED after 3 more seconds (5 total)
      Timer(const Duration(seconds: 3), () {
        final innerList = _tenantMessages[tenantId];
        if (innerList != null) {
          final idx = innerList.indexWhere((m) => m['messageId'] == messageId);
          if (idx != -1) {
            final shouldFail = (messageId.hashCode % 10) == 0;
            innerList[idx]['status'] = shouldFail ? 'FAILED' : 'DELIVERED';
          }
        }
      });
    });
  }

  // Helper: Create an HTTP response stream
  http.StreamedResponse _jsonResponse(
    int statusCode,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) {
    final bodyBytes = utf8.encode(jsonEncode(body));
    final respHeaders = {
      'Content-Type': 'application/json',
      ...?headers,
    };
    return http.StreamedResponse(
      Stream.value(bodyBytes),
      statusCode,
      contentLength: bodyBytes.length,
      headers: respHeaders,
    );
  }

  // Helper: Read the body of an incoming HTTP request
  Future<String> _readRequestBody(http.BaseRequest request) async {
    if (request is http.Request) {
      return request.body;
    }
    final bytes = await request.finalize().toBytes();
    return utf8.decode(bytes);
  }
}
