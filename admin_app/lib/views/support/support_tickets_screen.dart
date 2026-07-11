import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/support_ticket.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

class SupportTicketsScreen extends StatelessWidget {
  final bool embedded;
  const SupportTicketsScreen({super.key, this.embedded = false});

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
    final body = ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: mockTickets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final t = mockTickets[i];
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
            ],
          ),
        );
      },
    );

    if (embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("Support Tickets")), body: body);
  }
}
