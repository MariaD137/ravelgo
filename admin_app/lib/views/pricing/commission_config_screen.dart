import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

/// The single most important pricing control in RavelGo: the platform-wide
/// commission rate per service (RIDE/DELIVERY), read from and written to the
/// real `CommissionConfig` table — never a hardcoded constant. Writing is
/// Super-Admin only ("settings:write"); every other Admin preset can still
/// see the live rate, with a clear read-only message instead of a crash if
/// they attempt a save.
class CommissionConfigScreen extends StatefulWidget {
  const CommissionConfigScreen({super.key});

  @override
  State<CommissionConfigScreen> createState() => _CommissionConfigScreenState();
}

class _CommissionConfigScreenState extends State<CommissionConfigScreen> {
  bool _loading = true;
  String? _error;
  List<CommissionConfigRow> _rows = const [];
  // Set once a save attempt actually comes back 403, so we can show a
  // permanent "you can view but not edit this" banner instead of only a
  // one-off snackbar.
  bool _readOnly = false;

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
      final rows = await AdminApi.commissionConfig();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _edit(CommissionConfigRow row) async {
    final ctrl = TextEditingController(text: (row.rate * 100).toStringAsFixed(1));
    final newPercent = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${_serviceLabel(row.service)} commission'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RavelGo takes this share of every completed ${row.service == 'RIDE' ? 'ride' : 'delivery'} fare. '
              'This is the platform default — individual categories or vehicle classes may still override it.',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Commission rate',
                suffixText: '%',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, double.tryParse(ctrl.text.trim())),
            child: const Text('Next'),
          ),
        ],
      ),
    );
    if (newPercent == null) return;
    if (newPercent < 0 || newPercent > 100) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Enter a percentage between 0 and 100.')));
      }
      return;
    }
    final newRate = newPercent / 100;
    if (!mounted) return;

    // Confirm — this changes real money flow on every ride/delivery from now
    // on (never retroactive), so mirror the payout-completion confirm step.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change commission rate?'),
        content: Text(
          '${_serviceLabel(row.service)} commission changes from ${(row.rate * 100).toStringAsFixed(1)}% to '
          '${newPercent.toStringAsFixed(1)}%.\n\n'
          'This takes effect immediately for every ${row.service == 'RIDE' ? 'ride' : 'delivery'} settled after '
          'this change. Already-completed transactions keep the rate they were charged at.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm change')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final updated = await AdminApi.updateCommissionRate(row.service, newRate);
      if (!mounted) return;
      setState(() {
        _rows = [for (final r in _rows) if (r.service == row.service) updated else r];
        _readOnly = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Commission rate updated. Recorded in the audit log.')));
    } catch (e) {
      if (!mounted) return;
      final is403 = e is ApiException && e.statusCode == 403;
      if (is403) setState(() => _readOnly = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(is403
            ? 'Only a Super Admin can change commission rates. You can still view the current rate.'
            : (e is ApiException ? e.message : e.toString())),
      ));
    }
  }

  String _serviceLabel(String service) => service == 'RIDE' ? 'Rides' : 'Delivery';
  IconData _serviceIcon(String service) => service == 'RIDE' ? Icons.directions_car_outlined : Icons.local_shipping_outlined;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Commission Config')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null ? _errView() : _body()),
    );
  }

  Widget _errView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ),
      );

  Widget _body() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.medium),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: AppColors.textSecondary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'RavelGo’s default commission is 20% of every completed ride or delivery. Set here, '
                    'platform-wide, per service — never hardcoded. Individual ride categories or delivery '
                    'vehicle classes can still override it.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          if (_readOnly)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.medium),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline, size: 18, color: AppColors.warning),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'View-only for your role. Only a Super Admin can change commission rates.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.warning, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ..._rows.map((row) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: AppComponents.cardDecoration(),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(AppRadius.small),
                      ),
                      child: Icon(_serviceIcon(row.service), color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_serviceLabel(row.service), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          const SizedBox(height: 3),
                          Text(
                            row.updatedAt == null
                                ? 'Never changed'
                                : 'Updated ${formatFriendlyDate(row.updatedAt!)} by ${row.updatedBy ?? 'unknown'}',
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    AppComponents.badge('${(row.rate * 100).toStringAsFixed(1)}%', color: AppColors.primary),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _edit(row),
                      tooltip: 'Edit commission rate',
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
