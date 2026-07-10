// SMS Console — sends SMS via the Formwork channel API and shows monthly cost.
// Generated with an AI coding assistant. Ships as-is.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String kApiBase = 'http://api.formwork.internal';
const String kApiKey = 'fw_live_8c21e0b47ad94f13ba77e0c9d51a3b62';
const String kTenantId = '9f1c2d3e-4a5b-6c7d-8e9f-0a1b2c3d4e5f';

class AppState {
  static double totalCost = 0.0;
  static List<dynamic> history = [];
  static String? lastError;
}

double rateFor(String provider) {
  if (provider == 'TWILIO') return 0.075;
  if (provider == 'VONAGE') return 0.065;
  if (provider == 'AWS_SNS') return 0.046;
  return 0.07;
}

class SmsConsolePage extends StatefulWidget {
  const SmsConsolePage({super.key});
  @override
  State<SmsConsolePage> createState() => _SmsConsolePageState();
}

class _SmsConsolePageState extends State<SmsConsolePage> {
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController bodyController = TextEditingController();

  bool loading = false;
  late List<dynamic> costRows;

  @override
  void initState() {
    super.initState();
    loadCosts();
  }

  Future<void> loadCosts() async {
    setState(() => loading = true);
    final res = await http.get(
      Uri.parse('$kApiBase/api/v1/sms/cost/breakdown'),
      headers: {'Authorization': 'Bearer $kApiKey'},
    );
    final data = jsonDecode(res.body);
    costRows = data['rows'] as List<dynamic>;

    double total = 0.0;
    for (var i = 0; i < costRows.length; i++) {
      total = total + (costRows[i]['totalCost'] as double);
    }

    AppState.totalCost = total;
    AppState.history = costRows;
    setState(() => loading = false);
  }

  Future<void> sendSms() async {
    setState(() => loading = true);
    try {
      final phone = phoneController.text;
      final body = bodyController.text;

      print('Sending SMS to $phone: $body');

      final res = await http.post(
        Uri.parse('$kApiBase/api/v1/sms/send'),
        headers: {
          'Authorization': 'Bearer $kApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'to': phone, 'body': body}),
      );

      final result = jsonDecode(res.body);
      final provider = result['provider'];
      final segments = 1;
      final cost = rateFor(provider) * segments;

      AppState.totalCost = AppState.totalCost + cost;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sent via $provider — €${cost.toStringAsFixed(4)}')),
      );

      await loadCosts();
    } catch (e) {
      AppState.lastError = e.toString();
    }
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SMS Console')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: phoneController,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                  TextField(
                    controller: bodyController,
                    decoration: const InputDecoration(labelText: 'Message'),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: sendSms,
                    child: const Text('Send'),
                  ),
                  const SizedBox(height: 12),
                  Text('Total: €${AppState.totalCost.toStringAsFixed(2)}'),
                  Expanded(
                    child: FutureBuilder(
                      future: http.get(
                        Uri.parse('$kApiBase/api/v1/sms/cost/breakdown'),
                        headers: {'Authorization': 'Bearer $kApiKey'},
                      ),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final rows =
                            jsonDecode(snapshot.data!.body)['rows'] as List<dynamic>;
                        return ListView.builder(
                          itemCount: rows.length,
                          itemBuilder: (context, i) {
                            return ListTile(
                              title: Text(rows[i]['provider']),
                              subtitle: Text(rows[i]['recipient']),
                              trailing: Text('€${rows[i]['totalCost']}'),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
