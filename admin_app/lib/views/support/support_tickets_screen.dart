import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/support_ticket.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/support_api.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

class SupportTicketsScreen extends StatefulWidget {
  final bool embedded;
  final SupportApi? supportApi;
  const SupportTicketsScreen({super.key, this.embedded = false, this.supportApi});

  @override
  State<SupportTicketsScreen> createState() => _SupportTicketsScreenState();
}

class _SupportTicketsScreenState extends State<SupportTicketsScreen> {
  late final SupportApi _api = widget.supportApi ?? SupportApi(ApiClient());
  late Future<List<SupportTicket>> _future;
  final Set<String> _mutatingIds = {};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<SupportTicket>> _load() async {
    final raw = await _api.listAll();
    return raw.map(SupportTicket.fromJson).toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _advance(SupportTicket ticket, TicketStatus next) async {
    setState(() => _mutatingIds.add(ticket.id));
    try {
      await _api.setStatus(ticket.id, ticketStatusToApi(next));
      if (!mounted) return;
      await _refresh();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update ticket: $err')));
    } finally {
      if (mounted) setState(() => _mutatingIds.remove(ticket.id));
    }
  }

  Color _statusColor(TicketStatus s) {
    switch (s) {
      case TicketStatus.open:
        return AppColors.danger;
      case TicketStatus.inProgress:
        return AppColors.warning;
      case TicketStatus.resolved:
        return AppColors.success;
    }
  }

  String _statusLabel(TicketStatus s) {
    switch (s) {
      case TicketStatus.open:
        return "Open";
      case TicketStatus.inProgress:
        return "In progress";
      case TicketStatus.resolved:
        return "Resolved";
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<SupportTicket>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                const SizedBox(height: 80),
                Center(child: Text('Failed to load tickets: ${snapshot.error}', textAlign: TextAlign.center)),
                const SizedBox(height: 12),
                Center(child: TextButton(onPressed: _refresh, child: const Text('Retry'))),
              ],
            );
          }
          final tickets = snapshot.data ?? const [];
          if (tickets.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 80),
                Center(child: Text('No support tickets yet.', style: TextStyle(color: Colors.black54))),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: tickets.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final t = tickets[i];
              final mutating = _mutatingIds.contains(t.id);
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: AppComponents.cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(t.subject, style: const TextStyle(fontWeight: FontWeight.w600))),
                        AppComponents.badge(_statusLabel(t.status), color: _statusColor(t.status)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text("${t.category} · from ${t.from}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 2),
                    Text(formatFriendlyDate(t.createdAt), style: const TextStyle(fontSize: 11, color: Colors.black45)),
                    if (t.status != TicketStatus.resolved) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: mutating
                              ? null
                              : () => _advance(t, t.status == TicketStatus.open ? TicketStatus.inProgress : TicketStatus.resolved),
                          child: Text(mutating
                              ? 'Working…'
                              : (t.status == TicketStatus.open ? 'Mark in progress' : 'Mark resolved')),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("Support Tickets")), body: body);
  }
}
