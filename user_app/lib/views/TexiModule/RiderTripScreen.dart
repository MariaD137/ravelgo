import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/Model/ride_lifecycle.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';
import 'package:ravelgo_user_app/views/TexiModule/RateDriverScreen.dart';
import 'package:ravelgo_user_app/views/bottommenu/BottomNavigationView.dart';

/// Rider-side trip lifecycle: accepted -> en route -> arrived -> in progress
/// -> completed -> rate driver.
///
/// BACKEND BOUNDARY (SIMULATED): in production these transitions arrive from
/// the realtime trip feed driven by the driver's app. That feed does not
/// exist yet, so a local timer stands in for it and advances the stages;
/// `_advance` is the single integration point to replace with real events.
class RiderTripScreen extends StatefulWidget {
  final RideOffer offer;
  const RiderTripScreen({super.key, required this.offer});

  @override
  State<RiderTripScreen> createState() => _RiderTripScreenState();
}

class _RiderTripScreenState extends State<RiderTripScreen> {
  RideStatus _status = RideStatus.accepted;
  Timer? _feedTimer;

  static const _progression = [
    RideStatus.accepted,
    RideStatus.enRoute,
    RideStatus.arrived,
    RideStatus.inProgress,
    RideStatus.completed,
  ];

  @override
  void initState() {
    super.initState();
    // SIMULATION of the realtime driver-status feed (see class doc).
    _feedTimer = Timer.periodic(const Duration(seconds: 6), (_) => _advance());
  }

  @override
  void dispose() {
    _feedTimer?.cancel();
    super.dispose();
  }

  void _advance() {
    final i = _progression.indexOf(_status);
    if (i < 0 || i + 1 >= _progression.length) return;
    setState(() => _status = _progression[i + 1]);
    if (_status == RideStatus.completed) {
      _feedTimer?.cancel();
      Future.microtask(() {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => RateDriverScreen(offer: widget.offer)),
        );
      });
    }
  }

  bool get _canCancel => _status == RideStatus.accepted || _status == RideStatus.enRoute;

  Future<void> _cancelRide() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this ride?'),
        content: const Text('Your driver is on the way. Are you sure you want to cancel?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep ride')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel ride', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _feedTimer?.cancel();
    setState(() => _status = RideStatus.cancelled);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => BottomNavigationView()),
      (route) => false,
    );
  }

  void _contactSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Contact ${widget.offer.driverName}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            ListTile(
              leading: const Icon(Icons.call_outlined),
              title: const Text('In-app voice call'),
              subtitle: const Text('Your phone number stays private'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.message_outlined),
              title: const Text("I'm at the pickup point"),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.message_outlined),
              title: const Text('Running 2 minutes late'),
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  int get _stageIndex => _progression.indexOf(_status).clamp(0, _progression.length - 1);

  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Stack(
              children: [
                Image.asset('assets/fake_map.png', width: double.infinity, height: 260, fit: BoxFit.cover),
                Positioned(
                  top: 12,
                  left: 12,
                  child: CircleAvatar(
                    backgroundColor: AppColors.surface,
                    child: IconButton(
                      icon: const Icon(Icons.shield_outlined, color: AppColors.error),
                      onPressed: _contactSheet,
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: List.generate(_progression.length - 1, (i) {
                        final done = i < _stageIndex;
                        return Expanded(
                          child: Container(
                            height: 4,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: done ? AppColors.primary : AppColors.border,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 16),
                    Text(_status.label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(_status.description, style: const TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(radius: 24, backgroundImage: AssetImage(o.avatarAsset)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(o.driverName,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                                Text('${o.vehicle}  ·  ★ ${o.rating}',
                                    style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          IconButton(onPressed: _contactSheet, icon: const Icon(Icons.call_outlined)),
                          IconButton(onPressed: _contactSheet, icon: const Icon(Icons.message_outlined)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Fare: ${o.fare}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          _status == RideStatus.enRoute ? '${o.etaMinutes} mins away' : '',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (_canCancel)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _cancelRide,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('Cancel ride'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
