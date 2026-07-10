import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/exceptions/api_exceptions.dart';
import '../../domain/repositories/sms_repository.dart';
import '../../data/repositories/network_sms_repository.dart';
import 'tenant_bloc.dart';

abstract class SmsSendEvent {}

class SendSmsRequested extends SmsSendEvent {
  final String to;
  final String body;
  SendSmsRequested({required this.to, required this.body});
}

class ClearSendSmsStatus extends SmsSendEvent {}

enum SmsSendStatus { initial, loading, success, failure }

class SmsSendState {
  final SmsSendStatus status;
  final String? error;
  final int? rateLimitedSeconds;

  const SmsSendState({
    required this.status,
    this.error,
    this.rateLimitedSeconds,
  });

  factory SmsSendState.initial() => const SmsSendState(status: SmsSendStatus.initial);
  factory SmsSendState.loading() => const SmsSendState(status: SmsSendStatus.loading);
  factory SmsSendState.success() => const SmsSendState(status: SmsSendStatus.success);
  factory SmsSendState.failure(String error, {int? rateLimitedSeconds}) => SmsSendState(
        status: SmsSendStatus.failure,
        error: error,
        rateLimitedSeconds: rateLimitedSeconds,
      );
}

class SmsSendBloc extends Bloc<SmsSendEvent, SmsSendState> {
  final SmsRepository _repository;
  final TenantBloc _tenantBloc;

  SmsSendBloc({
    required SmsRepository repository,
    required TenantBloc tenantBloc,
  })  : _repository = repository,
        _tenantBloc = tenantBloc,
        super(SmsSendState.initial()) {
    on<SendSmsRequested>(_onSendSmsRequested);
    on<ClearSendSmsStatus>((event, emit) => emit(SmsSendState.initial()));
  }

  Future<void> _onSendSmsRequested(SendSmsRequested event, Emitter<SmsSendState> emit) async {
    emit(SmsSendState.loading());
    try {
      await _executeSend(event.to, event.body);
      emit(SmsSendState.success());
    } on TokenExpiredException {
      // Auto Auth Token Recovery:
      try {
        final repo = _repository as NetworkSmsRepository;
        // Obtain new token using static refresh token
        final result = await repo.refreshToken('mock_refresh_token');
        final newToken = result['accessToken'] as String;

        // Update token in TenantBloc
        _tenantBloc.add(UpdateTenantToken(newToken));

        // Retry original request
        await _executeSend(event.to, event.body);
        emit(SmsSendState.success());
      } catch (e) {
        emit(SmsSendState.failure('Auth refresh failed: ${e.toString()}'));
      }
    } on RateLimitException catch (e) {
      emit(SmsSendState.failure(
        e.message,
        rateLimitedSeconds: e.retryAfterSeconds,
      ));
    } on ApiException catch (e) {
      emit(SmsSendState.failure(e.message));
    } catch (e) {
      emit(SmsSendState.failure('Unexpected error: ${e.toString()}'));
    }
  }

  Future<void> _executeSend(String to, String body) async {
    final activeTenant = _tenantBloc.state.activeTenant;
    await _repository.sendSms(
      tenantId: activeTenant.id,
      token: activeTenant.token,
      to: to,
      body: body,
    );
  }
}
