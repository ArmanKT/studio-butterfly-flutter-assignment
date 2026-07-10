import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/models/tenant.dart';

abstract class TenantEvent {}

class SwitchTenant extends TenantEvent {
  final Tenant tenant;
  SwitchTenant(this.tenant);
}

class UpdateTenantToken extends TenantEvent {
  final String token;
  UpdateTenantToken(this.token);
}

class ForceExpireToken extends TenantEvent {}

class TenantState {
  final List<Tenant> availableTenants;
  final Tenant activeTenant;

  const TenantState({
    required this.availableTenants,
    required this.activeTenant,
  });
}

class TenantBloc extends Bloc<TenantEvent, TenantState> {
  TenantBloc()
      : super(
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
    on<SwitchTenant>((event, emit) {
      emit(TenantState(
        availableTenants: state.availableTenants,
        activeTenant: event.tenant,
      ));
    });

    on<UpdateTenantToken>((event, emit) {
      final updatedActive = state.activeTenant.copyWith(token: event.token);
      final updatedList = state.availableTenants.map((t) {
        return t.id == state.activeTenant.id ? updatedActive : t;
      }).toList();

      emit(TenantState(
        availableTenants: updatedList,
        activeTenant: updatedActive,
      ));
    });

    on<ForceExpireToken>((event, emit) {
      add(UpdateTenantToken('expired_token'));
    });
  }
}
