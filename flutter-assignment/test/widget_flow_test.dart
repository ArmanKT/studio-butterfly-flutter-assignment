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
import 'package:flutter_assignment/features/sms_console/presentation/widgets/sms_form_widget.dart';

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
          BlocProvider<TenantBloc>(
            create: (context) => TenantBloc(
              repository: repository,
            ),
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
          home: Scaffold(
            body: SmsFormWidget(),
          ),
        ),
      ),
    );
  }

  testWidgets('SMS Form validates empty inputs and shows error validation text', (WidgetTester tester) async {
    await tester.pumpWidget(createTestWidget());

    // Verify input elements are rendered
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Recipient Phone (E.164)'), findsOneWidget);
    expect(find.text('Message Body'), findsOneWidget);

    // Tap send on empty form to trigger validation
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    // Verify validation errors are present
    expect(find.text('Recipient phone is required'), findsOneWidget);
    expect(find.text('Message body is required'), findsOneWidget);
  });

  testWidgets('SMS Form validates non-E.164 phone formats', (WidgetTester tester) async {
    await tester.pumpWidget(createTestWidget());

    // Enter invalid phone format and valid body
    await tester.enterText(find.byType(TextFormField).first, '12345');
    await tester.enterText(find.byType(TextFormField).last, 'Hello world');
    await tester.pump();

    // Tap send
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    // Verify phone validation fails but body validation passes
    expect(find.text('Must be valid E.164 format (e.g. +4915112345678)'), findsOneWidget);
    expect(find.text('Message body is required'), findsNothing);
  });

  testWidgets('SMS Form handles 429 rate limit triggers and updates button cooldown countdown', (WidgetTester tester) async {
    // Enable rate limit simulation in mock HTTP engine
    MockApiSettings.force429Error = true;
    MockApiSettings.rateLimitRetryAfterSeconds = 3;
    MockApiSettings.networkDelay = Duration.zero; // Instant response for deterministic testing

    await tester.pumpWidget(createTestWidget());

    // Enter valid data
    await tester.enterText(find.byType(TextFormField).first, '+4915112345678');
    await tester.enterText(find.byType(TextFormField).last, 'Testing rate limits');
    await tester.pump();

    // Tap Send
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(); // Process tap microtasks and resolve instantaneous HTTP future
    await tester.pump(); // Render updated rate limited state

    // Check button shows cooldown and is disabled
    final btnFinder = find.byType(ElevatedButton);
    final ElevatedButton btnWidget = tester.widget(btnFinder);
    expect(btnWidget.onPressed, isNull); // Disabled
    expect(find.text('Rate Limited (3 s)'), findsOneWidget);

    // Advance time by 1 second
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Rate Limited (2 s)'), findsOneWidget);

    // Advance time by 1 more second
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Rate Limited (1 s)'), findsOneWidget);

    // Advance time by 1 more second (total 3s cooldown finished)
    await tester.pump(const Duration(seconds: 1));
    
    // Check that button is re-enabled and displays "Send SMS"
    final enabledBtnWidget = tester.widget<ElevatedButton>(btnFinder);
    expect(enabledBtnWidget.onPressed, isNotNull); // Re-enabled
    expect(find.text('Send SMS'), findsOneWidget);
  });
}
