import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

/// Append-only log of privileged admin actions AND significant system events
/// an admin should be able to trace (e.g. a trip reaching COMPLETED) — see
/// backend/src/lib/audit.ts. GET /api/admin/audit.
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  bool _loading = true;
  String? _error;
  List<AuditEntry> _entries = const [];

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
      final entries = await AdminApi.audit();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.statusCode == 403
            ? 'Sign in as an admin to view the audit log.'
            : e.toString();
        _loading = false;
      });
    }
  }

  IconData _icon(String action) {
    if (action.startsWith('DRIVER')) return Icons.badge_outlined;
    if (action.startsWith('DOCUMENT')) return Icons.description_outlined;
    if (action.startsWith('RIDER')) return Icons.person_outline;
    if (action.startsWith('TRIP')) return Icons.directions_car_outlined;
    return Icons.history;
  }

  String _pretty(String s) =>
      s.isEmpty ? '' : s.toLowerCase().replaceAll('_', ' ').replaceFirstMapped(RegExp(r'^\w'), (m) => m[0]!.toUpperCase());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audit log')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null ? _errorView() : _list()),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );

  Widget _list() {
    if (_entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No activity recorded yet.\nDriver approvals, document reviews, rider suspensions and completed trips appear here.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final e = _entries[i];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: AppComponents.cardDecoration(),
            child: Row(
              children: [
                Icon(_icon(e.action), size: 20, color: AppColors.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_pretty(e.action), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                      const SizedBox(height: 2),
                      Text("${e.entityType}${e.entityId != null ? ' · ${e.entityId}' : ''}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Text(formatFriendlyDate(e.createdAt), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          );
        },
      ),
    );
  }
}
