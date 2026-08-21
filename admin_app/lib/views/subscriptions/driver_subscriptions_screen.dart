import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class DriverSubscriptionsScreen extends StatefulWidget {
  const DriverSubscriptionsScreen({super.key});

  @override
  State<DriverSubscriptionsScreen> createState() => _DriverSubscriptionsScreenState();
}

class _DriverSubscriptionsScreenState extends State<DriverSubscriptionsScreen> {
  bool _loading = true;
  String? _error;
  int _subscribedCount = 0;
  String _monthlyRevenue = '₦0';
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _drivers = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final response = await ApiClient().get('/subscriptions');
      final data = response as Map<String, dynamic>;
      if (!mounted) return;

      final plans = List<Map<String, dynamic>>.from(data['plans'] ?? []);
      final drivers = List<Map<String, dynamic>>.from(data['drivers'] ?? data['data'] ?? []);
      final subscribedCount = (data['subscribedCount'] as int?) ??
          drivers.where((d) => d['subscriptionActive'] == true || d['status'] == 'ACTIVE').length;
      final revenue = data['monthlyRevenue'];

      String revenueStr;
      if (revenue is num) {
        if (revenue >= 1000000) {
          revenueStr = '₦${(revenue / 1000000).toStringAsFixed(2)}M';
        } else if (revenue >= 1000) {
          revenueStr = '₦${(revenue / 1000).toStringAsFixed(0)},000';
        } else {
          revenueStr = '₦${revenue.toStringAsFixed(0)}';
        }
      } else {
        revenueStr = revenue?.toString() ?? '₦0';
      }

      setState(() {
        _subscribedCount = subscribedCount;
        _monthlyRevenue = revenueStr;
        _plans = plans;
        _drivers = drivers;
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

  String _driverName(Map<String, dynamic> d) {
    final user = d['user'] as Map<String, dynamic>?;
    if (user != null) {
      return '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim();
    }
    return d['name'] as String? ?? 'Unknown';
  }

  bool _isSubscribed(Map<String, dynamic> d) {
    return d['subscriptionActive'] == true || d['status'] == 'ACTIVE';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text("Driver Subscriptions")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Driver Subscriptions")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                const Text('Failed to load subscriptions', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.black54), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () { setState(() { _loading = true; _error = null; }); _loadData(); },
                  child: const Text("Retry"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Driver Subscriptions")),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(child: AppComponents.statCard("Subscribed drivers", "$_subscribedCount", Icons.workspace_premium_outlined, color: AppColors.success)),
                const SizedBox(width: 12),
                Expanded(child: AppComponents.statCard("Monthly plan revenue", _monthlyRevenue, Icons.payments_outlined, color: AppColors.info)),
              ],
            ),
            const SizedBox(height: 20),
            AppComponents.sectionTitle("Plans"),
            Container(
              decoration: AppComponents.cardDecoration(),
              child: Column(
                children: _plans.isEmpty
                    ? [
                        AppComponents.tile(
                          title: "Weekly",
                          subtitle: "₦3,500 / week",
                          leading: Icons.calendar_view_week,
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Plan management coming soon')),
                            );
                          },
                        ),
                        AppComponents.divider(),
                        AppComponents.tile(
                          title: "Monthly",
                          subtitle: "₦12,000 / month",
                          leading: Icons.calendar_month_outlined,
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Plan management coming soon')),
                            );
                          },
                        ),
                        AppComponents.divider(),
                        AppComponents.tile(
                          title: "Quarterly",
                          subtitle: "₦32,000 / quarter",
                          leading: Icons.event_repeat_outlined,
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Plan management coming soon')),
                            );
                          },
                        ),
                      ]
                    : _plans.asMap().entries.expand((entry) {
                        final plan = entry.value;
                        final name = plan['name'] as String? ?? '';
                        final price = plan['price'] as String? ?? '';
                        final widgets = <Widget>[
                          AppComponents.tile(
                            title: name,
                            subtitle: price,
                            leading: Icons.workspace_premium_outlined,
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Plan management coming soon')),
                              );
                            },
                          ),
                        ];
                        if (entry.key < _plans.length - 1) {
                          widgets.add(AppComponents.divider());
                        }
                        return widgets;
                      }).toList(),
              ),
            ),
            const SizedBox(height: 20),
            AppComponents.sectionTitle("Drivers"),
            if (_drivers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text("No drivers found", style: TextStyle(color: Colors.black54))),
              )
            else
              ..._drivers.map((d) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: AppComponents.cardDecoration(),
                    child: Row(
                      children: [
                        Expanded(child: Text(_driverName(d), style: const TextStyle(fontWeight: FontWeight.w600))),
                        AppComponents.badge(
                          _isSubscribed(d) ? "Subscribed" : "Not subscribed",
                          color: _isSubscribed(d) ? AppColors.success : Colors.grey,
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}
