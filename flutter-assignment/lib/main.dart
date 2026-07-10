import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'core/network/mock_http_client.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_cubit.dart';
import 'features/sms_console/data/repositories/network_sms_repository.dart';
import 'features/sms_console/domain/repositories/sms_repository.dart';
import 'features/sms_console/presentation/blocs/tenant_bloc.dart';
import 'features/sms_console/presentation/blocs/sms_send_bloc.dart';
import 'features/sms_console/presentation/blocs/message_history_bloc.dart';
import 'features/sms_console/presentation/blocs/cost_breakdown_bloc.dart';
import 'features/sms_console/presentation/screens/sms_console_screen.dart';

void main() {
  // Initialize mock network layer
  final mockClient = MockHttpClient();
  final repository = NetworkSmsRepository(
    client: mockClient,
    baseUrl: 'http://api.formwork.internal',
  );

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<http.Client>.value(value: mockClient),
        RepositoryProvider<SmsRepository>.value(value: repository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(
            create: (context) => ThemeCubit(),
          ),
          BlocProvider<TenantBloc>(
            create: (context) => TenantBloc(),
          ),
          BlocProvider<SmsSendBloc>(
            create: (context) => SmsSendBloc(
              repository: context.read<SmsRepository>(),
              tenantBloc: context.read<TenantBloc>(),
            ),
          ),
          BlocProvider<MessageHistoryBloc>(
            create: (context) => MessageHistoryBloc(
              repository: context.read<SmsRepository>(),
              tenantBloc: context.read<TenantBloc>(),
            ),
          ),
          BlocProvider<CostBreakdownBloc>(
            create: (context) => CostBreakdownBloc(
              repository: context.read<SmsRepository>(),
              tenantBloc: context.read<TenantBloc>(),
            ),
          ),
        ],
        child: const SmsConsoleApp(),
      ),
    ),
  );
}

class SmsConsoleApp extends StatelessWidget {
  const SmsConsoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeMode>(
      builder: (context, mode) {
        return MaterialApp(
          title: 'Formwork SMS Console',
          themeMode: mode,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          home: const SmsConsoleScreen(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
