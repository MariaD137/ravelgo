import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/rider_record.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/rider_api.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/riders/rider_detail_screen.dart';

class RiderListScreen extends StatefulWidget {
  final RiderApi? riderApi;
  const RiderListScreen({super.key, this.riderApi});

  @override
  State<RiderListScreen> createState() => _RiderListScreenState();
}

class _RiderListScreenState extends State<RiderListScreen> {
  late final RiderApi _api = widget.riderApi ?? RiderApi(ApiClient());
  late Future<List<RiderRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<RiderRecord>> _load() async {
    final raw = await _api.listRiders();
    return raw.map(RiderRecord.fromJson).toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Riders")),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<RiderRecord>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(child: Text('Failed to load riders: ${snapshot.error}', textAlign: TextAlign.center)),
                  const SizedBox(height: 12),
                  Center(child: TextButton(onPressed: _refresh, child: const Text('Retry'))),
                ],
              );
            }
            final riders = snapshot.data ?? const [];
            if (riders.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 80),
                  Center(child: Text('No riders yet.', style: TextStyle(color: Colors.black54))),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: riders.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final r = riders[i];
                return InkWell(
                  onTap: () async {
                    final changed = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(builder: (_) => RiderDetailScreen(riderId: r.id, riderApi: _api)),
                    );
                    if (changed == true) _refresh();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: AppComponents.cardDecoration(),
                    child: Row(
                      children: [
                        const CircleAvatar(radius: 22, backgroundColor: Color(0xFFF0F0F0), child: Icon(Icons.person, color: Colors.black45)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                if (r.isLoyaltyMember) ...[const SizedBox(width: 6), AppComponents.badge("Loyalty")],
                              ]),
                              const SizedBox(height: 4),
                              Text(r.email, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                            ],
                          ),
                        ),
                        AppComponents.badge(
                          r.status == RiderStatus.active ? "Active" : "Suspended",
                          color: r.status == RiderStatus.active ? AppColors.success : AppColors.danger,
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
