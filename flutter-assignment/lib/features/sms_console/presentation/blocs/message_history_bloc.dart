import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/exceptions/api_exceptions.dart';
import '../../domain/models/sms_models.dart';
import '../../domain/repositories/sms_repository.dart';
import '../../data/repositories/network_sms_repository.dart';
import 'tenant_bloc.dart';

abstract class MessageHistoryEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class FetchMessageHistory extends MessageHistoryEvent {
  final bool isRefresh;
  FetchMessageHistory({this.isRefresh = false});

  @override
  List<Object?> get props => [isRefresh];
}

class LoadMoreMessageHistory extends MessageHistoryEvent {}

class PollMessageHistoryStatuses extends MessageHistoryEvent {}

enum MessageHistoryStatus { initial, loading, loaded, failure, loadingMore }

class MessageHistoryState extends Equatable {
  final MessageHistoryStatus status;
  final List<SmsMessage> messages;
  final String? nextCursor;
  final String? error;

  const MessageHistoryState({
    required this.status,
    required this.messages,
    this.nextCursor,
    this.error,
  });

  factory MessageHistoryState.initial() => const MessageHistoryState(
        status: MessageHistoryStatus.initial,
        messages: [],
      );

  MessageHistoryState copyWith({
    MessageHistoryStatus? status,
    List<SmsMessage>? messages,
    String? nextCursor,
    bool clearCursor = false,
    String? error,
  }) {
    return MessageHistoryState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [status, messages, nextCursor, error];
}

class MessageHistoryBloc extends Bloc<MessageHistoryEvent, MessageHistoryState> {
  final SmsRepository _repository;
  final TenantBloc _tenantBloc;
  StreamSubscription? _tenantSubscription;
  Timer? _pollingTimer;

  MessageHistoryBloc({
    required SmsRepository repository,
    required TenantBloc tenantBloc,
  })  : _repository = repository,
        _tenantBloc = tenantBloc,
        super(MessageHistoryState.initial()) {
    on<FetchMessageHistory>(_onFetchMessageHistory);
    on<LoadMoreMessageHistory>(_onLoadMoreMessageHistory);
    on<PollMessageHistoryStatuses>(_onPollMessageHistoryStatuses);

    // Reactively listen to TenantBloc to wipe and refresh message logs on switch
    _tenantSubscription = _tenantBloc.stream.listen((tenantState) {
      add(FetchMessageHistory(isRefresh: true));
    });

    // Fetch initial history for the active tenant on startup
    add(FetchMessageHistory());
  }

  Future<void> _onFetchMessageHistory(FetchMessageHistory event, Emitter<MessageHistoryState> emit) async {
    if (event.isRefresh) {
      _stopPolling();
    }
    emit(state.copyWith(status: MessageHistoryStatus.loading));
    try {
      final response = await _fetchPage(null);
      emit(MessageHistoryState(
        status: MessageHistoryStatus.loaded,
        messages: response.items,
        nextCursor: response.nextCursor,
      ));
      _evaluatePolling(response.items);
    } on TokenExpiredException {
      try {
        final repo = _repository as NetworkSmsRepository;
        final result = await repo.refreshToken('mock_refresh_token');
        final newToken = result['accessToken'] as String;
        _tenantBloc.add(UpdateTenantToken(newToken));

        final response = await _fetchPage(null);
        emit(MessageHistoryState(
          status: MessageHistoryStatus.loaded,
          messages: response.items,
          nextCursor: response.nextCursor,
        ));
        _evaluatePolling(response.items);
      } catch (e) {
        emit(state.copyWith(status: MessageHistoryStatus.failure, error: e.toString()));
      }
    } catch (e) {
      emit(state.copyWith(
        status: MessageHistoryStatus.failure,
        error: e.toString(),
      ));
    }
  }

  Future<void> _onLoadMoreMessageHistory(LoadMoreMessageHistory event, Emitter<MessageHistoryState> emit) async {
    if (state.status == MessageHistoryStatus.loadingMore || state.nextCursor == null) return;

    emit(state.copyWith(status: MessageHistoryStatus.loadingMore));
    try {
      final response = await _fetchPage(state.nextCursor);
      final newMessages = List<SmsMessage>.from(state.messages)..addAll(response.items);

      emit(state.copyWith(
        status: MessageHistoryStatus.loaded,
        messages: newMessages,
        nextCursor: response.nextCursor,
        clearCursor: response.nextCursor == null,
      ));
      _evaluatePolling(newMessages);
    } on TokenExpiredException {
      try {
        final repo = _repository as NetworkSmsRepository;
        final result = await repo.refreshToken('mock_refresh_token');
        final newToken = result['accessToken'] as String;
        _tenantBloc.add(UpdateTenantToken(newToken));

        final response = await _fetchPage(state.nextCursor);
        final newMessages = List<SmsMessage>.from(state.messages)..addAll(response.items);

        emit(state.copyWith(
          status: MessageHistoryStatus.loaded,
          messages: newMessages,
          nextCursor: response.nextCursor,
          clearCursor: response.nextCursor == null,
        ));
        _evaluatePolling(newMessages);
      } catch (e) {
        emit(state.copyWith(status: MessageHistoryStatus.loaded));
      }
    } catch (e) {
      emit(state.copyWith(status: MessageHistoryStatus.loaded)); // Silently fail and restore loaded state
    }
  }

  Future<void> _onPollMessageHistoryStatuses(PollMessageHistoryStatuses event, Emitter<MessageHistoryState> emit) async {
    try {
      final response = await _fetchPage(null);
      // Merge status updates for matched messages
      final mergedMessages = state.messages.map((existing) {
        final updated = response.items.firstWhere(
          (item) => item.messageId == existing.messageId,
          orElse: () => existing,
        );
        return updated;
      }).toList();

      emit(state.copyWith(messages: mergedMessages));
      _evaluatePolling(mergedMessages);
    } catch (_) {
      // Ignore polling errors to not disrupt UI logs display
    }
  }

  Future<MessagesPageResponse> _fetchPage(String? cursor) async {
    final activeTenant = _tenantBloc.state.activeTenant;
    return await _repository.getMessages(
      tenantId: activeTenant.id,
      token: activeTenant.token,
      cursor: cursor,
    );
  }

  void _evaluatePolling(List<SmsMessage> items) {
    final hasPending = items.any((m) => m.status == SmsStatus.accepted || m.status == SmsStatus.sent);
    if (hasPending) {
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  void _startPolling() {
    if (_pollingTimer != null) return;
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      add(PollMessageHistoryStatuses());
    });
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  @override
  Future<void> close() {
    _tenantSubscription?.cancel();
    _stopPolling();
    return super.close();
  }
}
