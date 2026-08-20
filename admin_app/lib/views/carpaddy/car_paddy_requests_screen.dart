import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

class CarPaddyRequestsScreen extends StatefulWidget {
  const CarPaddyRequestsScreen({super.key});

  @override
  State<CarPaddyRequestsScreen> createState() => _CarPaddyRequestsScreenState();
}

class _CarPaddyRequestsScreenState extends State<CarPaddyRequestsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final response = await ApiClient().get('/car-paddy');
      final page = response as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _requests = List<Map<String, dynamic>>.from(page['data'] ?? []);
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
      await ApiClient().patch('/car-paddy/$id/status', body: {'status': status});
      if (!mounted) return;
      setState(() {
        _requests[index]['status'] = status;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Request ${status == "APPROVED" ? "approved" : "rejected"} successfully')),
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
      case 'SUBMITTED':
        return Colors.grey;
      case 'IN_REVIEW':
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
      case 'SUBMITTED':
        return 'Submitted';
      case 'IN_REVIEW':
        return 'In review';
      case 'APPROVED':
        return 'Approved';
      case 'REJECTED':
        return 'Rejected';
      default:
        return status ?? 'Unknown';
    }
  }

  String _driverName(Map<String, dynamic> r) {
    final driver = r['driver'] as Map<String, dynamic>?;
    if (driver != null) {
      final user = driver['user'] as Map<String, dynamic>? ?? driver;
      return '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim();
    }
    return r['driverName'] as String? ?? 'Unknown';
  }

  bool _isActionable(String? status) {
    return status == 'IN_REVIEW' || status == 'SUBMITTED';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text("Car Paddy Requests")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Car Paddy Requests")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                const Text('Failed to load requests', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
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
      appBar: AppBar(title: const Text("Car Paddy Requests")),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _requests.isEmpty
            ? ListView(children: const [SizedBox(height: 100), Center(child: Text("No requests", style: TextStyle(color: Colors.black54)))])
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _requests.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final r = _requests[i];
                  final status = r['status'] as String?;
                  final id = r['id'] as String? ?? '';
                  final plateNumber = r['plateNumber'] as String? ?? r['licensePlate'] as String? ?? '';
                  final submittedOn = r['createdAt'] != null
                      ? DateTime.tryParse(r['createdAt'].toString()) ?? DateTime.now()
                      : DateTime.now();

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: AppComponents.cardDecoration(),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("${_driverName(r)} · $plateNumber", style: const TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text("Submitted ${formatShortDate(submittedOn)}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                            ],
                          ),
                        ),
                        if (_isActionable(status))
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.close, color: AppColors.danger),
                                onPressed: () => _updateStatus(id, 'REJECTED', i),
                              ),
                              IconButton(
                                icon: const Icon(Icons.check, color: AppColors.success),
                                onPressed: () => _updateStatus(id, 'APPROVED', i),
                              ),
                            ],
                          )
                        else
                          AppComponents.badge(_statusLabel(status), color: _statusColor(status)),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
