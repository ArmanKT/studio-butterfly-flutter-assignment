import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/exceptions/api_exceptions.dart';
import '../../domain/models/sms_models.dart';
import '../../domain/repositories/sms_repository.dart';
import '../../data/repositories/network_sms_repository.dart';
import 'tenant_bloc.dart';

abstract class CostBreakdownEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class FetchCostBreakdown extends CostBreakdownEvent {}

enum CostBreakdownStatus { initial, loading, loaded, failure }

class CostBreakdownState extends Equatable {
  final CostBreakdownStatus status;
  final CostBreakdown? breakdown;
  final String? error;

  const CostBreakdownState({
    required this.status,
    this.breakdown,
    this.error,
  });

  factory CostBreakdownState.initial() => const CostBreakdownState(status: CostBreakdownStatus.initial);
  factory CostBreakdownState.loading() => const CostBreakdownState(status: CostBreakdownStatus.loading);

  CostBreakdownState copyWith({
    CostBreakdownStatus? status,
    CostBreakdown? breakdown,
    String? error,
  }) {
    return CostBreakdownState(
      status: status ?? this.status,
      breakdown: breakdown ?? this.breakdown,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [status, breakdown, error];
}

class CostBreakdownBloc extends Bloc<CostBreakdownEvent, CostBreakdownState> {
  final SmsRepository _repository;
  final TenantBloc _tenantBloc;
  StreamSubscription? _tenantSubscription;

  CostBreakdownBloc({
    required SmsRepository repository,
    required TenantBloc tenantBloc,
  })  : _repository = repository,
        _tenantBloc = tenantBloc,
        super(CostBreakdownState.initial()) {
    on<FetchCostBreakdown>(_onFetchCostBreakdown);

    // Reactively listen to TenantBloc to wipe and refresh cost stats on switch
    _tenantSubscription = _tenantBloc.stream.listen((tenantState) {
      add(FetchCostBreakdown());
    });

    // Fetch initial breakdown for the active tenant on startup
    add(FetchCostBreakdown());
  }

  Future<void> _onFetchCostBreakdown(FetchCostBreakdown event, Emitter<CostBreakdownState> emit) async {
    emit(CostBreakdownState.loading());
    try {
      final breakdown = await _fetchBreakdown();
      emit(CostBreakdownState(status: CostBreakdownStatus.loaded, breakdown: breakdown));
    } on TokenExpiredException {
      try {
        final repo = _repository as NetworkSmsRepository;
        final result = await repo.refreshToken('mock_refresh_token');
        final newToken = result['accessToken'] as String;
        _tenantBloc.add(UpdateTenantToken(newToken));

        final breakdown = await _fetchBreakdown();
        emit(CostBreakdownState(status: CostBreakdownStatus.loaded, breakdown: breakdown));
      } catch (e) {
        emit(CostBreakdownState(status: CostBreakdownStatus.failure, error: e.toString()));
      }
    } catch (e) {
      emit(CostBreakdownState(status: CostBreakdownStatus.failure, error: e.toString()));
    }
  }

  Future<CostBreakdown> _fetchBreakdown() async {
    final activeTenant = _tenantBloc.state.activeTenant;
    final now = DateTime.now();
    final fromDate = now.subtract(const Duration(days: 30));
    final toDate = now.add(const Duration(days: 1)); // Buffer to include current actions

    return await _repository.getCostBreakdown(
      tenantId: activeTenant.id,
      token: activeTenant.token,
      from: fromDate,
      to: toDate,
    );
  }

  @override
  Future<void> close() {
    _tenantSubscription?.cancel();
    return super.close();
  }
}
