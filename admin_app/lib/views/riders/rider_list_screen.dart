import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/rider_record.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/riders/rider_detail_screen.dart';

class RiderListScreen extends StatefulWidget {
  const RiderListScreen({super.key});

  @override
  State<RiderListScreen> createState() => _RiderListScreenState();
}

class _RiderListScreenState extends State<RiderListScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _riders = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final response = await ApiClient().get('/riders');
      final page = response as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _riders = List<Map<String, dynamic>>.from(page['data'] ?? []);
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

  RiderRecord _toRiderRecord(Map<String, dynamic> json) {
    final suspended = json['suspended'] == true;
    return RiderRecord(
      id: json['id'] ?? '',
      name: '${json['firstName'] ?? ''} ${json['lastName'] ?? ''}'.trim(),
      email: json['email'] ?? '',
      totalTrips: (json['ridesAsRider'] as List?)?.length ?? 0,
      rating: 0.0,
      status: suspended ? RiderStatus.suspended : RiderStatus.active,
      isLoyaltyMember: json['isLoyaltyMember'] == true,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text("Riders")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Riders")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text('Failed to load riders', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.black54), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: () { setState(() { _loading = true; _error = null; }); _loadData(); }, child: const Text("Retry")),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Riders")),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _riders.isEmpty
            ? ListView(children: const [SizedBox(height: 100), Center(child: Text("No riders found", style: TextStyle(color: Colors.black54)))])
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _riders.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final r = _toRiderRecord(_riders[i]);
                  return InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RiderDetailScreen(rider: r))),
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
                                Text("${r.totalTrips} trips · ★ ${r.rating}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
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
              ),
      ),
    );
  }
}
