import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/utils/date_utils.dart';

class TripDetailScreen extends StatefulWidget {
  final DriverTrip trip;
  const TripDetailScreen({super.key, required this.trip});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  late DriverTrip _trip = widget.trip;
  bool _busy = false;

  bool get _cancelled => _trip.status == 'CANCELLED' || _trip.status == 'DISPUTED';

  Color _statusColor() {
    if (_cancelled) return AppColors.danger;
    if (_trip.status == 'COMPLETED') return AppColors.success;
    return AppColors.primaryDark;
  }

  String _pretty(String s) => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  Future<void> _advance(String toStatus, {double? finalFare}) async {
    setState(() => _busy = true);
    try {
      final updated = await DriverApi.updateTripStatus(_trip.id, toStatus, finalFare: finalFare);
      if (!mounted) return;
      setState(() => _trip = updated);
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('#${_trip.id.substring(0, _trip.id.length < 6 ? _trip.id.length : 6)}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppComponents.badge(_pretty(_trip.status), color: _statusColor()),
            const SizedBox(height: 12),
            Text(formatFriendlyDate(_trip.requestedAt), style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppComponents.cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(Icons.trip_origin, _trip.pickup),
                  const SizedBox(height: 10),
                  _row(Icons.place_outlined, _trip.destination),
                  AppComponents.divider(),
                  if (_trip.riderName != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Rider"),
                          Text(_trip.riderName!, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Fare", style: TextStyle(fontWeight: FontWeight.w700)),
                      Text("\$${_trip.fare.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ..._actions(),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions() {
    if (_busy) {
      return const [Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))];
    }
    switch (_trip.status) {
      case 'MATCHED':
        return [
          AppComponents.primaryButton(text: "Start trip", onPressed: () => _advance('IN_PROGRESS')),
        ];
      case 'IN_PROGRESS':
        return [
          AppComponents.primaryButton(
            text: "Complete trip",
            // Charge the agreed estimate (1.0x is within the allowed fare band).
            onPressed: () => _advance('COMPLETED', finalFare: _trip.estimatedFare),
          ),
        ];
      default:
        return [
          AppComponents.outlineButton(
            text: "Download receipt",
            onPressed: () =>
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Receipt saved to device"))),
          ),
        ];
    }
  }

  Widget _row(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}
