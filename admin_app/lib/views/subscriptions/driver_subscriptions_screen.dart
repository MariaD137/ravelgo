import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/driver_record.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/driver_api.dart';
import 'package:ravelgo_admin/services/api/subscription_api.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class DriverSubscriptionsScreen extends StatefulWidget {
  final DriverApi? driverApi;
  final SubscriptionApi? subscriptionApi;
  const DriverSubscriptionsScreen({super.key, this.driverApi, this.subscriptionApi});

  @override
  State<DriverSubscriptionsScreen> createState() => _DriverSubscriptionsScreenState();
}

class _DriverSubscriptionsScreenState extends State<DriverSubscriptionsScreen> {
  late final DriverApi _driverApi = widget.driverApi ?? DriverApi(ApiClient());
  late final SubscriptionApi _subscriptionApi = widget.subscriptionApi ?? SubscriptionApi(ApiClient());

  late Future<(List<DriverRecord>, List<Map<String, dynamic>>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<DriverRecord>, List<Map<String, dynamic>>)> _load() async {
    final results = await Future.wait([_driverApi.listDrivers(), _subscriptionApi.listPlans()]);
    final drivers = results[0].map(DriverRecord.fromJson).toList();
    final plans = results[1];
    return (drivers, plans);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Driver Subscriptions")),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<(List<DriverRecord>, List<Map<String, dynamic>>)>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(child: Text('Failed to load: ${snapshot.error}', textAlign: TextAlign.center)),
                  const SizedBox(height: 12),
                  Center(child: TextButton(onPressed: _refresh, child: const Text('Retry'))),
                ],
              );
            }
            final (drivers, plans) = snapshot.data!;
            final subscribed = drivers.where((d) => d.subscriptionActive).length;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                AppComponents.statCard("Subscribed drivers", "$subscribed", Icons.workspace_premium_outlined, color: AppColors.success),
                const SizedBox(height: 20),
                AppComponents.sectionTitle("Plans"),
                if (plans.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text("No subscription plans configured.", style: TextStyle(color: Colors.black54)),
                  )
                else
                  Container(
                    decoration: AppComponents.cardDecoration(),
                    child: Column(
                      children: [
                        for (var i = 0; i < plans.length; i++) ...[
                          if (i > 0) AppComponents.divider(),
                          AppComponents.tile(
                            title: plans[i]['name'] as String,
                            subtitle: '₦${(plans[i]['priceMonthly'] as num).toStringAsFixed(0)} / month',
                            leading: Icons.calendar_month_outlined,
                            onTap: () {},
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                AppComponents.sectionTitle("Drivers"),
                if (drivers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text("No drivers yet.", style: TextStyle(color: Colors.black54)),
                  ),
                ...drivers.map((d) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: AppComponents.cardDecoration(),
                      child: Row(
                        children: [
                          Expanded(child: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                          AppComponents.badge(
                            d.subscriptionActive ? "Subscribed" : "Not subscribed",
                            color: d.subscriptionActive ? AppColors.success : Colors.grey,
                          ),
                        ],
                      ),
                    )),
              ],
            );
          },
        ),
      ),
    );
  }
}
