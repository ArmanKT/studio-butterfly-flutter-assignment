import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../blocs/message_history_bloc.dart';
import '../../domain/models/sms_models.dart';

class MessageHistoryListWidget extends StatefulWidget {
  const MessageHistoryListWidget({super.key});

  @override
  State<MessageHistoryListWidget> createState() => _MessageHistoryListWidgetState();
}

class _MessageHistoryListWidgetState extends State<MessageHistoryListWidget> {
  final _scrollController = ScrollController();
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Initial fetch of logs
    context.read<MessageHistoryBloc>().add(FetchMessageHistory());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isBottom) {
      context.read<MessageHistoryBloc>().add(LoadMoreMessageHistory());
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    // Load more when user is 100 pixels away from the bottom of the list
    return currentScroll >= (maxScroll - 100);
  }

  Color _getStatusColor(SmsStatus status) {
    switch (status) {
      case SmsStatus.delivered:
        return Colors.green;
      case SmsStatus.sent:
        return Colors.blue;
      case SmsStatus.accepted:
        return Colors.orange;
      case SmsStatus.failed:
        return Colors.red;
    }
  }

  Widget _buildStatusChip(SmsStatus status) {
    final color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Text(
        status.toApiString(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MessageHistoryBloc, MessageHistoryState>(
      builder: (context, state) {
        if (state.status == MessageHistoryStatus.loading) {
          return const Card(
            child: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (state.status == MessageHistoryStatus.failure) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load message history\n${state.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      onPressed: () {
                        context.read<MessageHistoryBloc>().add(FetchMessageHistory(isRefresh: true));
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final messages = state.messages;

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Message History',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    Text(
                      '${messages.length} messages',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      context.read<MessageHistoryBloc>().add(FetchMessageHistory(isRefresh: true));
                    },
                    child: messages.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 100),
                              Center(
                                child: Text(
                                  'No messages found for this tenant.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            itemCount: messages.length + (state.nextCursor != null ? 1 : 0),
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemBuilder: (context, index) {
                              if (index == messages.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16.0),
                                  child: Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  ),
                                );
                              }

                              final msg = messages[index];

                              return Semantics(
                                label: 'SMS sent to ${msg.recipient} at ${_dateFormat.format(msg.sentAt.toLocal())}. Status: ${msg.status.toApiString()}',
                                child: Card(
                                  margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    leading: CircleAvatar(
                                      backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                      child: Icon(
                                        Icons.sms_outlined,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            msg.recipient,
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _buildStatusChip(msg.status),
                                      ],
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Segments: ${msg.segmentCount} • Cost: ${msg.cost} EUR',
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _dateFormat.format(msg.sentAt.toLocal()),
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
