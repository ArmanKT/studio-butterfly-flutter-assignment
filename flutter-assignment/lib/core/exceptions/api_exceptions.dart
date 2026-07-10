class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? errorCode;

  ApiException(this.message, {this.statusCode, this.errorCode});

  @override
  String toString() => errorCode != null ? 'ApiException[$errorCode]: $message' : 'ApiException: $message';
}

class ValidationException extends ApiException {
  ValidationException(super.message, {super.statusCode, super.errorCode});
}

class RateLimitException extends ApiException {
  final int retryAfterSeconds;

  RateLimitException(super.message, {required this.retryAfterSeconds, super.statusCode})
      : super(errorCode: 'RATE_LIMIT');

  @override
  String toString() => 'RateLimitException: $message. Retry after $retryAfterSeconds seconds.';
}

class GatewayException extends ApiException {
  GatewayException(super.message, {super.statusCode})
      : super(errorCode: 'BAD_GATEWAY');
}

class TokenExpiredException extends ApiException {
  TokenExpiredException(super.message)
      : super(statusCode: 403, errorCode: 'TOKEN_EXPIRED');
}

class UnauthorizedException extends ApiException {
  UnauthorizedException(super.message, {super.statusCode})
      : super(errorCode: 'UNAUTHORIZED');
}
