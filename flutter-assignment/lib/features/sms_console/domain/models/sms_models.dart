class Money {
  final int microUnits; // 1 unit = 10000 microUnits (4 decimal places)

  const Money(this.microUnits);

  factory Money.parse(String value) {
    final cleanValue = value.trim();
    final parts = cleanValue.split('.');
    if (parts.isEmpty) return const Money(0);
    
    final whole = int.tryParse(parts[0]) ?? 0;
    if (parts.length == 1) {
      return Money(whole * 10000);
    }
    
    var fractionStr = parts[1];
    if (fractionStr.length > 4) {
      fractionStr = fractionStr.substring(0, 4);
    } else {
      fractionStr = fractionStr.padRight(4, '0');
    }
    final fraction = int.tryParse(fractionStr) ?? 0;
    
    final isNegative = whole < 0 || (whole == 0 && cleanValue.startsWith('-'));
    final total = whole.abs() * 10000 + fraction;
    return Money(isNegative ? -total : total);
  }

  Money operator +(Money other) => Money(microUnits + other.microUnits);
  Money operator -(Money other) => Money(microUnits - other.microUnits);
  Money operator *(int factor) => Money(microUnits * factor);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Money && runtimeType == other.runtimeType && microUnits == other.microUnits;

  @override
  int get hashCode => microUnits.hashCode;

  @override
  String toString() {
    final isNegative = microUnits < 0;
    final absUnits = microUnits.abs();
    final whole = absUnits ~/ 10000;
    final fraction = absUnits % 10000;
    final sign = isNegative ? '-' : '';
    return '$sign$whole.${fraction.toString().padLeft(4, '0')}';
  }
}

enum SmsStatus {
  accepted,
  sent,
  delivered,
  failed;

  static SmsStatus fromString(String value) {
    switch (value.toUpperCase()) {
      case 'ACCEPTED':
        return SmsStatus.accepted;
      case 'SENT':
        return SmsStatus.sent;
      case 'DELIVERED':
        return SmsStatus.delivered;
      case 'FAILED':
        return SmsStatus.failed;
      default:
        throw ArgumentError('Unknown status: $value');
    }
  }

  String toApiString() => name.toUpperCase();
}

class SmsMessage {
  final String messageId;
  final String recipient;
  final SmsStatus status;
  final int segmentCount;
  final Money cost;
  final DateTime sentAt;

  SmsMessage({
    required this.messageId,
    required this.recipient,
    required this.status,
    required this.segmentCount,
    required this.cost,
    required this.sentAt,
  });

  factory SmsMessage.fromJson(Map<String, dynamic> json) {
    return SmsMessage(
      messageId: json['messageId'] as String,
      recipient: json['recipient'] as String,
      status: SmsStatus.fromString(json['status'] as String),
      segmentCount: json['segmentCount'] as int,
      cost: Money.parse(json['cost'] as String),
      sentAt: DateTime.parse(json['sentAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'recipient': recipient,
      'status': status.toApiString(),
      'segmentCount': segmentCount,
      'cost': cost.toString(),
      'sentAt': sentAt.toIso8601String(),
    };
  }

  SmsMessage copyWith({
    String? messageId,
    String? recipient,
    SmsStatus? status,
    int? segmentCount,
    Money? cost,
    DateTime? sentAt,
  }) {
    return SmsMessage(
      messageId: messageId ?? this.messageId,
      recipient: recipient ?? this.recipient,
      status: status ?? this.status,
      segmentCount: segmentCount ?? this.segmentCount,
      cost: cost ?? this.cost,
      sentAt: sentAt ?? this.sentAt,
    );
  }
}

class SmsSendResponse {
  final String messageId;
  final String provider;
  final SmsStatus status;
  final int segmentCount;
  final Money cost;
  final String currency;

  SmsSendResponse({
    required this.messageId,
    required this.provider,
    required this.status,
    required this.segmentCount,
    required this.cost,
    required this.currency,
  });

  factory SmsSendResponse.fromJson(Map<String, dynamic> json) {
    return SmsSendResponse(
      messageId: json['messageId'] as String,
      provider: json['provider'] as String,
      status: SmsStatus.fromString(json['status'] as String),
      segmentCount: json['segmentCount'] as int,
      cost: Money.parse(json['cost'] as String),
      currency: json['currency'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'provider': provider,
      'status': status.toApiString(),
      'segmentCount': segmentCount,
      'cost': cost.toString(),
      'currency': currency,
    };
  }
}

class CostBreakdownRow {
  final String provider;
  final Money totalCost;
  final int messageCount;

  CostBreakdownRow({
    required this.provider,
    required this.totalCost,
    required this.messageCount,
  });

  factory CostBreakdownRow.fromJson(Map<String, dynamic> json) {
    return CostBreakdownRow(
      provider: json['provider'] as String,
      totalCost: Money.parse(json['totalCost'] as String),
      messageCount: json['messageCount'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider': provider,
      'totalCost': totalCost.toString(),
      'messageCount': messageCount,
    };
  }
}

class CostBreakdown {
  final String currency;
  final Money totalCost;
  final List<CostBreakdownRow> rows;

  CostBreakdown({
    required this.currency,
    required this.totalCost,
    required this.rows,
  });

  factory CostBreakdown.fromJson(Map<String, dynamic> json) {
    final rowsList = json['rows'] as List<dynamic>;
    return CostBreakdown(
      currency: json['currency'] as String,
      totalCost: Money.parse(json['totalCost'] as String),
      rows: rowsList
          .map((r) => CostBreakdownRow.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'currency': currency,
      'totalCost': totalCost.toString(),
      'rows': rows.map((r) => r.toJson()).toList(),
    };
  }
}

class MessagesPageResponse {
  final List<SmsMessage> items;
  final String? nextCursor;

  MessagesPageResponse({
    required this.items,
    this.nextCursor,
  });

  factory MessagesPageResponse.fromJson(Map<String, dynamic> json) {
    final itemsList = json['items'] as List<dynamic>;
    return MessagesPageResponse(
      items: itemsList
          .map((item) => SmsMessage.fromJson(item as Map<String, dynamic>))
          .toList(),
      nextCursor: json['nextCursor'] as String?,
    );
  }
}
