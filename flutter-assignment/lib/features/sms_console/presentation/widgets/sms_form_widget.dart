import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/sms_send_bloc.dart';
import '../blocs/message_history_bloc.dart';
import '../blocs/cost_breakdown_bloc.dart';

class SmsFormWidget extends StatefulWidget {
  const SmsFormWidget({super.key});

  @override
  State<SmsFormWidget> createState() => _SmsFormWidgetState();
}

class _SmsFormWidgetState extends State<SmsFormWidget> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _bodyController = TextEditingController();

  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;

  @override
  void dispose() {
    _phoneController.dispose();
    _bodyController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() {
      _cooldownSeconds = seconds;
    });

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_cooldownSeconds <= 1) {
        timer.cancel();
        setState(() {
          _cooldownSeconds = 0;
        });
      } else {
        setState(() {
          _cooldownSeconds--;
        });
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final phone = _phoneController.text.trim();
    final body = _bodyController.text.trim();

    context.read<SmsSendBloc>().add(SendSmsRequested(to: phone, body: body));
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('SmsFormWidget build called, state: ${context.read<SmsSendBloc>().state.status}');
    return BlocListener<SmsSendBloc, SmsSendState>(
      listener: (context, state) {
        if (state.status == SmsSendStatus.failure) {
          if (state.rateLimitedSeconds != null && state.rateLimitedSeconds! > 0) {
            _startCooldown(state.rateLimitedSeconds!);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.error ?? 'Failed to send SMS'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        } else if (state.status == SmsSendStatus.success) {
          _bodyController.clear();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('SMS successfully dispatched!'),
              backgroundColor: Colors.green,
            ),
          );
          context.read<MessageHistoryBloc>().add(FetchMessageHistory(isRefresh: true));
          context.read<CostBreakdownBloc>().add(FetchCostBreakdown());
        }
      },
      child: BlocBuilder<SmsSendBloc, SmsSendState>(
        builder: (context, state) {
          final isLoading = state.status == SmsSendStatus.loading;
          final isCooldown = _cooldownSeconds > 0;
          final isButtonDisabled = isLoading || isCooldown;

          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Compose SMS',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    // Recipient Phone Input (with semantic support)
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Recipient Phone (E.164)',
                        hintText: '+4915112345678',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Recipient phone is required';
                        }
                        final phoneRegex = RegExp(r'^\+[1-9]\d{6,14}$');
                        if (!phoneRegex.hasMatch(val.trim())) {
                          return 'Must be valid E.164 format (e.g. +4915112345678)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    // Message Body Input
                    TextFormField(
                      controller: _bodyController,
                      decoration: const InputDecoration(
                        labelText: 'Message Body',
                        hintText: 'Enter your SMS content here...',
                        prefixIcon: Icon(Icons.message_outlined),
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                      keyboardType: TextInputType.multiline,
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Message body is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    // Submit Button with Rate Limit state awareness
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: isButtonDisabled ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2.5),
                              )
                            : Text(
                                isCooldown ? 'Rate Limited ($_cooldownSeconds s)' : 'Send SMS',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
