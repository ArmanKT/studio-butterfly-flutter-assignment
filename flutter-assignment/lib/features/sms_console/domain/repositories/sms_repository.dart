import '../models/sms_models.dart';

abstract class SmsRepository {
  Future<SmsSendResponse> sendSms({
    required String tenantId,
    required String token,
    required String to,
    required String body,
    String? referenceId,
  });

  Future<MessagesPageResponse> getMessages({
    required String tenantId,
    required String token,
    String? cursor,
    int limit = 50,
  });

  Future<CostBreakdown> getCostBreakdown({
    required String tenantId,
    required String token,
    required DateTime from,
    required DateTime to,
  });
}
