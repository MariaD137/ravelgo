import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/support_ticket.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

class SupportTicketsScreen extends StatefulWidget {
  final bool embedded;
  const SupportTicketsScreen({super.key, this.embedded = false});

  @override
  State<SupportTicketsScreen> createState() => _SupportTicketsScreenState();
}

class _SupportTicketsScreenState extends State<SupportTicketsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tickets = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final response = await ApiClient().get('/support-tickets');
      final page = response as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _tickets = List<Map<String, dynamic>>.from(page['data'] ?? []);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'OPEN':
        return AppColors.danger;
      case 'IN_PROGRESS':
        return AppColors.warning;
      case 'RESOLVED':
        return AppColors.success;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'OPEN':
        return "Open";
      case 'IN_PROGRESS':
        return "In progress";
      case 'RESOLVED':
        return "Resolved";
      default:
        return status;
    }
  }

  String _userName(Map<String, dynamic> ticket) {
    final user = ticket['user'] as Map<String, dynamic>?;
    if (user == null) return 'Unknown';
    return '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      final loader = const Center(child: CircularProgressIndicator());
      if (widget.embedded) return loader;
      return Scaffold(appBar: AppBar(title: const Text("Support Tickets")), body: loader);
    }

    if (_error != null) {
      final errorView = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('Failed to load tickets', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.black54), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () { setState(() { _loading = true; _error = null; }); _loadData(); }, child: const Text("Retry")),
            ],
          ),
        ),
      );
      if (widget.embedded) return errorView;
      return Scaffold(appBar: AppBar(title: const Text("Support Tickets")), body: errorView);
    }

    final body = RefreshIndicator(
      onRefresh: _loadData,
      child: _tickets.isEmpty
          ? ListView(children: const [SizedBox(height: 100), Center(child: Text("No tickets found", style: TextStyle(color: Colors.black54)))])
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _tickets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final t = _tickets[i];
                final status = t['status'] as String? ?? 'OPEN';
                final createdAt = t['createdAt'] != null
                    ? DateTime.tryParse(t['createdAt'].toString()) ?? DateTime.now()
                    : DateTime.now();
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppComponents.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(t['subject'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
                          AppComponents.badge(_statusLabel(status), color: _statusColor(status)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text("${t['category'] ?? ''} · from ${_userName(t)}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      const SizedBox(height: 2),
                      Text(formatFriendlyDate(createdAt), style: const TextStyle(fontSize: 11, color: Colors.black45)),
                    ],
                  ),
                );
              },
            ),
    );

    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("Support Tickets")), body: body);
  }
}
