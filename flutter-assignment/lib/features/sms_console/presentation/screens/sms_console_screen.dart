import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/theme_cubit.dart';
import '../blocs/tenant_bloc.dart';
import '../widgets/sms_form_widget.dart';
import '../widgets/cost_breakdown_widget.dart';
import '../widgets/message_history_list_widget.dart';

class SmsConsoleScreen extends StatelessWidget {
  const SmsConsoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('SmsConsoleScreen build called');
    return BlocBuilder<ThemeCubit, ThemeMode>(
      builder: (context, themeMode) {
        return BlocBuilder<TenantBloc, TenantState>(
          builder: (context, tenantState) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Formwork SMS Console'),
                actions: [
                  // Theme Toggle Button
                  IconButton(
                    icon: Icon(
                      themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
                    ),
                    tooltip: 'Toggle Theme Mode',
                    onPressed: () {
                      context.read<ThemeCubit>().toggleTheme();
                    },
                  ),
                  // Force expire token button (for security review testing)
                  TextButton.icon(
                    icon: const Icon(Icons.security, size: 16),
                    label: const Text('Expire Token'),
                    onPressed: () {
                      context.read<TenantBloc>().add(ForceExpireToken());
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Access token expired. Next request will trigger auto token-refresh recovery.'),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 800;

                  // Header tenant switcher section
                  final tenantSwitcher = Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Card(
                      margin: EdgeInsets.zero,
                      elevation: 0.5,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: Theme.of(context).brightness == Brightness.light
                              ? Colors.grey.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.08),
                          width: 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                        child: Row(
                          children: [
                            // Circular icon container
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.corporate_fare_rounded,
                                color: Theme.of(context).colorScheme.primary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Tenant Scope',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                                  ),
                            ),
                            const SizedBox(width: 16),
                            // Vertical divider
                            Container(
                              height: 24,
                              width: 1,
                              color: Colors.grey.withValues(alpha: 0.2),
                            ),
                            const SizedBox(width: 16),
                            // Dropdown in customized style
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: tenantState.activeTenant.id,
                                  isExpanded: true,
                                  icon: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  dropdownColor: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  items: tenantState.availableTenants.map((tenant) {
                                    return DropdownMenuItem<String>(
                                      value: tenant.id,
                                      child: Text(
                                        tenant.name,
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (id) {
                                    if (id != null) {
                                      final selected = tenantState.availableTenants
                                          .firstWhere((t) => t.id == id);
                                      context.read<TenantBloc>().add(SwitchTenant(selected));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Switched to ${selected.name}'),
                                          duration: const Duration(seconds: 1),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );

                  if (isWide) {
                    // Desktop Split Layout (Side-by-side)
                    return Column(
                      children: [
                        tenantSwitcher,
                        const Expanded(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Left Column: Send SMS and Cost Summary
                                Expanded(
                                  flex: 5,
                                  child: SingleChildScrollView(
                                    child: Column(
                                      children: [
                                        SmsFormWidget(),
                                        SizedBox(height: 16),
                                        CostBreakdownWidget(),
                                      ],
                                    ),
                                  ),
                                ),
                                SizedBox(width: 20),
                                // Right Column: Paginated Message logs
                                Expanded(
                                  flex: 6,
                                  child: MessageHistoryListWidget(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  } else {
                    // Mobile Stacked Layout (Tabbed View)
                    return Column(
                      children: [
                        tenantSwitcher,
                        const Expanded(
                          child: DefaultTabController(
                            length: 2,
                            child: Column(
                              children: [
                                TabBar(
                                  tabs: [
                                    Tab(icon: Icon(Icons.send_outlined), text: 'Console'),
                                    Tab(icon: Icon(Icons.history_outlined), text: 'Logs'),
                                  ],
                                ),
                                Expanded(
                                  child: TabBarView(
                                    children: [
                                      // Tab 1: Form & Costs
                                      SingleChildScrollView(
                                        padding: EdgeInsets.all(16.0),
                                        child: Column(
                                          children: [
                                            SmsFormWidget(),
                                            SizedBox(height: 16),
                                            CostBreakdownWidget(),
                                          ],
                                        ),
                                      ),
                                      // Tab 2: Logs list
                                      Padding(
                                        padding: EdgeInsets.all(16.0),
                                        child: MessageHistoryListWidget(),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                },
              ),
            );
          },
        );
      },
    );
  }
}
