import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/support_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// Real support/dispute tickets for drivers — same backend contract
/// (POST/GET /api/support-tickets) as user_app's SupportView, just with
/// driver-relevant categories. There is no separate driver-only ticket
/// system: this reads/writes the exact same SupportTicket table, and the
/// backend already scopes "mine" to the caller's own User row regardless of
/// role, so a driver can never see a rider's (or another driver's) tickets.
class DriverSupportScreen extends StatefulWidget {
  const DriverSupportScreen({super.key});

  @override
  State<DriverSupportScreen> createState() => _DriverSupportScreenState();
}

class _DriverSupportScreenState extends State<DriverSupportScreen> {
  static const _categories = [
    'Trip or delivery dispute',
    'Payment or earnings issue',
    'Vehicle or document issue',
    'Account status / suspension',
    'App issue',
    'Something else',
  ];

  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<SupportTicket> _tickets = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tickets = await SupportApi.myTickets();
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'Could not load your support tickets.';
        _loading = false;
      });
    }
  }

  Future<void> _newTicket(String category) async {
    final controller = TextEditingController();
    final subject = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(category),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          minLines: 2,
          decoration: const InputDecoration(
            hintText: 'Describe the issue — include trip/delivery ID if relevant',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (subject == null || subject.isEmpty || !mounted) return;

    setState(() => _submitting = true);
    try {
      await SupportApi.createTicket(subject: subject, category: category);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Your request has been sent to support.')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : 'Could not submit this request. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Color _statusColor(String status) => switch (status) {
        'RESOLVED' => AppColors.success,
        'IN_PROGRESS' => AppColors.primary,
        _ => AppColors.textSecondary,
      };

  String _label(String status) =>
      status.isEmpty ? '' : status[0] + status.substring(1).toLowerCase().replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support & Disputes')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (_submitting) const LinearProgressIndicator(),
            const Text('Your requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_error!, style: const TextStyle(color: AppColors.danger)),
                    TextButton(onPressed: _load, child: const Text('Try again')),
                  ],
                ),
              )
            else if (_tickets.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No requests yet.', style: TextStyle(color: AppColors.textSecondary)),
              )
            else
              ..._tickets.map((t) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: AppComponents.cardDecoration(),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.subject, style: const TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(t.category, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        Text(
                          _label(t.status),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _statusColor(t.status)),
                        ),
                      ],
                    ),
                  )),
            const SizedBox(height: 20),
            const Text('What do you need help with?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            ..._categories.map((c) => Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(c),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _submitting ? null : () => _newTicket(c),
                    ),
                    const Divider(height: 1),
                  ],
                )),
          ],
        ),
      ),
    );
  }
}
