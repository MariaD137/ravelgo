import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/support_api.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class SupportView extends StatefulWidget {
  const SupportView({super.key});

  @override
  State<SupportView> createState() => _SupportViewState();
}

class _SupportViewState extends State<SupportView> {
  static const _categories = [
    'Ride booking issues',
    'Pricing and payments',
    'Ride experience & safety',
    'Lost & Found',
    'App and account issue',
    'Get help with something else',
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
      final t = await SupportApi.myTickets();
      if (!mounted) return;
      setState(() {
        _tickets = t;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.statusCode == 403
            ? 'Sign in as a rider to contact support.'
            : e.toString();
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
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(
            hintText: 'Briefly describe the issue',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Send'),
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
      final msg = e is ApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'RESOLVED':
        return AppColors.success;
      case 'IN_PROGRESS':
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }

  String _label(String s) => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
            boxShadow: [BoxShadow(color: AppColors.border, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: const [
                  BackButton(color: AppColors.textPrimary),
                  Spacer(),
                  Text('Support',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.normal, color: AppColors.textPrimary)),
                  Spacer(),
                  SizedBox(width: 64),
                ],
              ),
            ),
          ),
        ),
      ),
      backgroundColor: AppColors.surface,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (_submitting) const LinearProgressIndicator(),

            // Your existing tickets
            const Text('Your support requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_error!, style: const TextStyle(color: AppColors.error)),
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
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(10),
                    ),
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
                        Text(_label(t.status),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _statusColor(t.status))),
                      ],
                    ),
                  )),

            const SizedBox(height: 16),
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
