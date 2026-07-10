import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_assignment/core/exceptions/api_exceptions.dart';
import 'package:flutter_assignment/core/network/mock_http_client.dart';
import 'package:flutter_assignment/features/sms_console/data/repositories/network_sms_repository.dart';
import 'package:flutter_assignment/features/sms_console/domain/models/sms_models.dart';

void main() {
  group('Money Arithmetic Precision Tests', () {
    test('Double precision error demonstrating Bug #3', () {
      const double rate = 0.0079;
      const double multiplier = 3;
      final double doubleSum = rate * multiplier;

      // Demonstrates that standard float math is imprecise:
      // 0.0079 * 3 = 0.023700000000000002
      expect(doubleSum, isNot(equals(0.0237)));
      expect(doubleSum.toString(), equals('0.023700000000000002'));
    });

    test('Money minor units precision math guarantees exact billing results', () {
      final Money rate = Money.parse('0.0079');
      final Money decimalSum = rate * 3;

      // Exact mathematical precision maintained:
      expect(decimalSum.toString(), equals('0.0237'));
    });
  });

  group('Model Serialization Tests', () {
    test('SmsMessage parses decimal strings correctly without float conversion', () {
      final json = {
        'messageId': 'SM123',
        'recipient': '+4915*****78',
        'status': 'DELIVERED',
        'segmentCount': 2,
        'cost': '0.1500',
        'sentAt': '2026-07-09T08:14:22Z',
      };

      final msg = SmsMessage.fromJson(json);

      expect(msg.messageId, equals('SM123'));
      expect(msg.cost, equals(Money.parse('0.1500')));
      expect(msg.status, equals(SmsStatus.delivered));
    });

    test('CostBreakdown handles sums and aggregates with Money types', () {
      final json = {
        'currency': 'EUR',
        'totalCost': '12.4500',
        'rows': [
          {'provider': 'TWILIO', 'totalCost': '8.2500', 'messageCount': 110},
          {'provider': 'AWS_SNS', 'totalCost': '4.2000', 'messageCount': 90}
        ]
      };

      final breakdown = CostBreakdown.fromJson(json);

      expect(breakdown.currency, equals('EUR'));
      expect(breakdown.totalCost, equals(Money.parse('12.4500')));
      expect(breakdown.rows.length, equals(2));
      expect(breakdown.rows[0].provider, equals('TWILIO'));
      expect(breakdown.rows[0].totalCost, equals(Money.parse('8.2500')));
    });
  });

  group('Network Repository & Mock Client Integration Tests', () {
    late http.Client mockClient;
    late NetworkSmsRepository repository;
    const tenantId = '9f1c2d3e-4a5b-6c7d-8e9f-0a1b2c3d4e5f';
    const token = 'mock_token_A';

    setUp(() {
      MockApiSettings.reset();
      mockClient = MockHttpClient();
      repository = NetworkSmsRepository(client: mockClient, baseUrl: 'http://api.formwork.internal');
    });

    test('Successful SMS send returns response model matching API contract', () async {
      final response = await repository.sendSms(
        tenantId: tenantId,
        token: token,
        to: '+4915112345678',
        body: 'Testing clean architecture',
      );

      expect(response.messageId, startsWith('SM'));
      expect(response.status, equals(SmsStatus.accepted));
      expect(response.cost, isNotNull);
    });

    test('Rate-limiting 429 status code parses Retry-After header and throws RateLimitException', () async {
      MockApiSettings.force429Error = true;
      MockApiSettings.rateLimitRetryAfterSeconds = 7;

      expect(
        () => repository.sendSms(
          tenantId: tenantId,
          token: token,
          to: '+4915112345678',
          body: 'Rate limited text',
        ),
        throwsA(
          isA<RateLimitException>()
              .having((e) => e.retryAfterSeconds, 'retryAfterSeconds', equals(7))
              .having((e) => e.statusCode, 'statusCode', equals(429)),
        ),
      );
    });

    test('Upstream error 502 throws GatewayException', () async {
      MockApiSettings.force502Error = true;

      expect(
        () => repository.sendSms(
          tenantId: tenantId,
          token: token,
          to: '+4915112345678',
          body: 'Gateway error text',
        ),
        throwsA(
          isA<GatewayException>().having((e) => e.statusCode, 'statusCode', equals(502)),
        ),
      );
    });

    test('Invalid phone number E.164 formats throws ValidationException', () async {
      expect(
        () => repository.sendSms(
          tenantId: tenantId,
          token: token,
          to: '1511234', // Missing + and too short
          body: 'Invalid phone format test',
        ),
        throwsA(
          isA<ValidationException>().having((e) => e.errorCode, 'errorCode', equals('INVALID_PHONE_NUMBER')),
        ),
      );
    });

    test('Tenant switcher token expired forces TokenExpiredException', () async {
      expect(
        () => repository.sendSms(
          tenantId: tenantId,
          token: 'expired_token', // Force expire token in mock engine
          to: '+4915112345678',
          body: 'Expired session',
        ),
        throwsA(isA<TokenExpiredException>()),
      );
    });
  });
}
