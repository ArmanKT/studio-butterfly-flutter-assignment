import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_assignment/core/network/mock_http_client.dart';
import 'package:flutter_assignment/features/sms_console/domain/repositories/sms_repository.dart';
import 'package:flutter_assignment/features/sms_console/data/repositories/network_sms_repository.dart';
import 'package:flutter_assignment/features/sms_console/presentation/blocs/tenant_bloc.dart';
import 'package:flutter_assignment/features/sms_console/presentation/blocs/sms_send_bloc.dart';
import 'package:flutter_assignment/features/sms_console/presentation/blocs/message_history_bloc.dart';
import 'package:flutter_assignment/features/sms_console/presentation/blocs/cost_breakdown_bloc.dart';
import 'package:flutter_assignment/core/theme/theme_cubit.dart';
import 'package:flutter_assignment/features/sms_console/presentation/screens/sms_console_screen.dart';

void main() {
  late MockHttpClient mockClient;
  late SmsRepository repository;

  setUp(() {
    MockApiSettings.reset();
    mockClient = MockHttpClient();
    repository = NetworkSmsRepository(client: mockClient, baseUrl: 'http://api.formwork.internal');
  });

  Widget createTestWidget() {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<http.Client>.value(value: mockClient),
        RepositoryProvider<SmsRepository>.value(value: repository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(
            create: (context) => ThemeCubit()..setTheme(ThemeMode.light),
          ),
          BlocProvider<TenantBloc>(
            create: (context) => TenantBloc(),
          ),
          BlocProvider<SmsSendBloc>(
            create: (context) => SmsSendBloc(
              repository: repository,
              tenantBloc: context.read<TenantBloc>(),
            ),
          ),
          BlocProvider<MessageHistoryBloc>(
            create: (context) => MessageHistoryBloc(
              repository: repository,
              tenantBloc: context.read<TenantBloc>(),
            ),
          ),
          BlocProvider<CostBreakdownBloc>(
            create: (context) => CostBreakdownBloc(
              repository: repository,
              tenantBloc: context.read<TenantBloc>(),
            ),
          ),
        ],
        child: const MaterialApp(
          home: SmsConsoleScreen(),
        ),
      ),
    );
  }

  testWidgets('SMS Console mobile layout golden test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();
    
    await expectLater(
      find.byType(SmsConsoleScreen),
      matchesGoldenFile('goldens/sms_console_mobile.png'),
    );

    // Reset size
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });

  testWidgets('SMS Console desktop layout golden test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();
    
    await expectLater(
      find.byType(SmsConsoleScreen),
      matchesGoldenFile('goldens/sms_console_desktop.png'),
    );

    // Reset size
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
