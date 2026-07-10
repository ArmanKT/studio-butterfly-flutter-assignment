import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../domain/models/tenant.dart';
import '../../domain/repositories/sms_repository.dart';

abstract class TenantEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class SwitchTenant extends TenantEvent {
  final Tenant tenant;
  SwitchTenant(this.tenant);

  @override
  List<Object?> get props => [tenant];
}

class UpdateTenantToken extends TenantEvent {
  final String token;
  UpdateTenantToken(this.token);

  @override
  List<Object?> get props => [token];
}

class ForceExpireToken extends TenantEvent {}

class LoadTenants extends TenantEvent {}

class TenantState extends Equatable {
  final List<Tenant> availableTenants;
  final Tenant activeTenant;

  const TenantState({
    required this.availableTenants,
    required this.activeTenant,
  });

  @override
  List<Object?> get props => [availableTenants, activeTenant];
}

class TenantBloc extends Bloc<TenantEvent, TenantState> {
  final SmsRepository _repository;

  TenantBloc({required SmsRepository repository})
      : _repository = repository,
        super(
          const TenantState(
            availableTenants: [
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
            ],
            activeTenant: Tenant(
              id: '9f1c2d3e-4a5b-6c7d-8e9f-0a1b2c3d4e5f',
              name: 'Tenant A (Seeded Data)',
              apiKey: 'fw_live_8c21e0b47ad94f13ba77e0c9d51a3b62',
              token: 'mock_token_A',
            ),
          ),
        ) {
    on<LoadTenants>(_onLoadTenants);
    on<SwitchTenant>(_onSwitchTenant);
    on<UpdateTenantToken>(_onUpdateTenantToken);
    on<ForceExpireToken>(_onForceExpireToken);

    // Dynamic load of available tenants from repository
    add(LoadTenants());
  }

  Future<void> _onLoadTenants(LoadTenants event, Emitter<TenantState> emit) async {
    try {
      final tenants = await _repository.getAvailableTenants();
      final active = tenants.any((t) => t.id == state.activeTenant.id)
          ? tenants.firstWhere((t) => t.id == state.activeTenant.id)
          : tenants.first;
      emit(TenantState(
        availableTenants: tenants,
        activeTenant: active,
      ));
    } catch (_) {
      // Fallback
    }
  }

  void _onSwitchTenant(SwitchTenant event, Emitter<TenantState> emit) {
    emit(TenantState(
      availableTenants: state.availableTenants,
      activeTenant: event.tenant,
    ));
  }

  void _onUpdateTenantToken(UpdateTenantToken event, Emitter<TenantState> emit) {
    final updatedActive = state.activeTenant.copyWith(token: event.token);
    final updatedList = state.availableTenants.map((t) {
      return t.id == state.activeTenant.id ? updatedActive : t;
    }).toList();

    emit(TenantState(
      availableTenants: updatedList,
      activeTenant: updatedActive,
    ));
  }

  void _onForceExpireToken(ForceExpireToken event, Emitter<TenantState> emit) {
    add(UpdateTenantToken('expired_token'));
  }
}
