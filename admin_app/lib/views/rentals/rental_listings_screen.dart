import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class RentalListingsScreen extends StatefulWidget {
  const RentalListingsScreen({super.key});

  @override
  State<RentalListingsScreen> createState() => _RentalListingsScreenState();
}

class _RentalListingsScreenState extends State<RentalListingsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _listings = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final response = await ApiClient().get('/rentals');
      final page = response as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _listings = List<Map<String, dynamic>>.from(page['data'] ?? []);
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

  Future<void> _updateStatus(String id, String status, int index) async {
    try {
      await ApiClient().patch('/rentals/$id/status', body: {'status': status});
      if (!mounted) return;
      setState(() {
        _listings[index]['status'] = status;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Listing ${status == "APPROVED" ? "approved" : "rejected"} successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'PENDING_APPROVAL':
        return AppColors.warning;
      case 'APPROVED':
        return AppColors.success;
      case 'REJECTED':
        return AppColors.danger;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'PENDING_APPROVAL':
        return 'Pending approval';
      case 'APPROVED':
        return 'Approved';
      case 'REJECTED':
        return 'Rejected';
      default:
        return status ?? 'Unknown';
    }
  }

  String _ownerName(Map<String, dynamic> l) {
    final owner = l['owner'] as Map<String, dynamic>?;
    if (owner != null) {
      return '${owner['firstName'] ?? ''} ${owner['lastName'] ?? ''}'.trim();
    }
    return l['ownerName'] as String? ?? 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text("Luxury Car Rental Listings")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Luxury Car Rental Listings")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                const Text('Failed to load listings', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
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
      appBar: AppBar(title: const Text("Luxury Car Rental Listings")),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _listings.isEmpty
            ? ListView(children: const [SizedBox(height: 100), Center(child: Text("No listings", style: TextStyle(color: Colors.black54)))])
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _listings.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final l = _listings[i];
                  final status = l['status'] as String?;
                  final id = l['id'] as String? ?? '';
                  final vehicle = l['vehicle'] as String? ?? l['make'] as String? ?? '';
                  final dailyRate = (l['dailyRate'] ?? l['pricePerDay'] ?? 0).toDouble();
                  final location = l['location'] as String? ?? '';

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: AppComponents.cardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text(vehicle, style: const TextStyle(fontWeight: FontWeight.w600))),
                            AppComponents.badge(_statusLabel(status), color: _statusColor(status)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text("Owner: ${_ownerName(l)} · $location", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                        const SizedBox(height: 6),
                        Text("₦${dailyRate.toStringAsFixed(0)} / day", style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (status == 'PENDING_APPROVAL') ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: AppComponents.outlineButton(
                                  text: "Reject",
                                  color: AppColors.danger,
                                  onPressed: () => _updateStatus(id, 'REJECTED', i),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: AppComponents.primaryButton(
                                  text: "Approve",
                                  onPressed: () => _updateStatus(id, 'APPROVED', i),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
