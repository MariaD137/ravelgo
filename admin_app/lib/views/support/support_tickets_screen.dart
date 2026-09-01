import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
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
  bool _busy = false;
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
      final t = await AdminApi.supportTickets();
      if (!mounted) return;
      setState(() {
        _tickets = t;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.statusCode == 403 ? 'Sign in as an admin to view tickets.' : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _setStatus(SupportTicket t, String status) async {
    setState(() => _busy = true);
    try {
      await AdminApi.setTicketStatus(t.id, status);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _color(String s) {
    switch (s) {
      case 'RESOLVED':
        return AppColors.success;
      case 'IN_PROGRESS':
        return AppColors.info;
      default:
        return AppColors.warning;
    }
  }

  String _label(String s) => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    final Widget body = _loading
        ? const Center(child: CircularProgressIndicator())
        : (_error != null ? _err(_error!, _load) : _list());
    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("Support Tickets")), body: body);
  }

  Widget _list() {
    if (_tickets.isEmpty) {
      return const Center(child: Text("No support tickets.", style: TextStyle(color: AppColors.textSecondary)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _tickets.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final t = _tickets[i];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(t.subject, style: const TextStyle(fontWeight: FontWeight.w600))),
                    AppComponents.badge(_label(t.status), color: _color(t.status)),
                  ],
                ),
                const SizedBox(height: 4),
                Text("${t.category} · ${t.userName.isEmpty ? 'User' : t.userName} · ${formatFriendlyDate(t.createdAt)}",
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (t.status != 'IN_PROGRESS')
                      TextButton(onPressed: _busy ? null : () => _setStatus(t, 'IN_PROGRESS'), child: const Text('Start')),
                    if (t.status != 'RESOLVED')
                      TextButton(onPressed: _busy ? null : () => _setStatus(t, 'RESOLVED'), child: const Text('Resolve')),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _err(String msg, VoidCallback retry) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
            TextButton(onPressed: retry, child: const Text('Try again')),
          ]),
        ),
      );
}
