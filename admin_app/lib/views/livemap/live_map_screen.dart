import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/couriers/courier_requests_screen.dart';
import 'package:ravelgo_admin/views/drivers/driver_detail_screen.dart';
import 'package:ravelgo_admin/views/rentals/rental_listings_screen.dart';
import 'package:ravelgo_admin/views/trips/trip_admin_detail_screen.dart';

/// RavelGo's live operations view: switches between Drivers, Riders,
/// Packages and Rentals, all backed by GET /api/admin/live-map — the single
/// authoritative aggregation endpoint (no per-tab tracking system). Drivers
/// keeps the interactive Google Map (real GPS pins); Riders/Packages/Rentals
/// are real-data lists — a rider or package pin only ever appears once a
/// real position has actually been reported, and a rental never shows a
/// location at all (no GPS source exists for RavelGo's self-drive rental
/// listings — see LiveMapRental's doc comment). Polls every 8s.
class LiveMapScreen extends StatefulWidget {
  final bool embedded;
  const LiveMapScreen({super.key, this.embedded = false});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

const _lagos = CameraPosition(target: LatLng(6.5244, 3.3792), zoom: 11);

enum _MonitorTab { drivers, riders, packages, rentals }

enum _StatusFilter { available, onTrip, logistics, incident, offline }

extension on _StatusFilter {
  String get apiValue => switch (this) {
        _StatusFilter.available => 'AVAILABLE',
        _StatusFilter.onTrip => 'ON_TRIP',
        _StatusFilter.logistics => 'LOGISTICS',
        _StatusFilter.incident => 'INCIDENT',
        _StatusFilter.offline => 'OFFLINE',
      };
  String get label => switch (this) {
        _StatusFilter.available => 'Available',
        _StatusFilter.onTrip => 'On trip',
        _StatusFilter.logistics => 'Logistics',
        _StatusFilter.incident => 'Incident',
        _StatusFilter.offline => 'Offline',
      };
  Color get color => switch (this) {
        _StatusFilter.available => AppColors.success,
        _StatusFilter.onTrip => AppColors.info,
        _StatusFilter.logistics => AppColors.warning,
        _StatusFilter.incident => AppColors.danger,
        _StatusFilter.offline => AppColors.textMuted,
      };
  double get hue => switch (this) {
        _StatusFilter.available => BitmapDescriptor.hueGreen,
        _StatusFilter.onTrip => BitmapDescriptor.hueAzure,
        _StatusFilter.logistics => BitmapDescriptor.hueOrange,
        _StatusFilter.incident => BitmapDescriptor.hueRed,
        _StatusFilter.offline => BitmapDescriptor.hueViolet,
      };
}

Color _presenceColor(String? presence) => switch (presence) {
      'LIVE' => AppColors.success,
      'STALE' => AppColors.warning,
      _ => AppColors.textMuted,
    };

String _presenceLabel(String? presence) => switch (presence) {
      'LIVE' => 'LIVE',
      'STALE' => 'STALE',
      _ => 'OFFLINE',
    };

Widget _presenceBadge(String? presence) {
  final color = _presenceColor(presence);
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.circle, size: 8, color: color),
      const SizedBox(width: 4),
      Text(_presenceLabel(presence), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    ],
  );
}

String _timeAgo(DateTime? t) {
  if (t == null) return 'No location reported yet';
  final secs = DateTime.now().difference(t).inSeconds;
  if (secs < 5) return 'Updated just now';
  if (secs < 60) return 'Updated $secs sec ago';
  final mins = secs ~/ 60;
  if (mins < 60) return 'Updated $mins min ago';
  return 'Updated ${mins ~/ 60}h ago';
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  Timer? _poll;
  bool _loading = true;
  String? _error;
  LiveMapData? _data;
  LiveMapDriver? _selectedDriver;
  LiveMapTrip? _selectedTrip;
  _MonitorTab _tab = _MonitorTab.drivers;
  final Set<_StatusFilter> _activeFilters = _StatusFilter.values.toSet();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final data = await AdminApi.liveMap();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _error = e is ApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  List<LiveMapDriver> get _visibleDrivers {
    final data = _data;
    if (data == null) return const [];
    return data.drivers.where((d) {
      if (!_activeFilters.map((f) => f.apiValue).contains(d.markerStatus)) return false;
      if (_search.trim().isEmpty) return true;
      return d.name.toLowerCase().contains(_search.trim().toLowerCase());
    }).toList();
  }

  Set<Marker> _markers() {
    final markers = <Marker>{};
    for (final d in _visibleDrivers) {
      final filter = _StatusFilter.values.firstWhere((f) => f.apiValue == d.markerStatus, orElse: () => _StatusFilter.offline);
      markers.add(Marker(
        markerId: MarkerId('driver-${d.driverId}'),
        position: LatLng(d.lat, d.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(filter.hue),
        onTap: () => setState(() {
          _selectedDriver = d;
          _selectedTrip = null;
        }),
      ));
    }
    return markers;
  }

  Set<Polyline> _routes() {
    final trips = _data?.trips ?? const [];
    final lines = <Polyline>{};
    for (final t in trips) {
      if (t.pickupLat == null || t.pickupLng == null || t.dropoffLat == null || t.dropoffLng == null) continue;
      lines.add(Polyline(
        polylineId: PolylineId('trip-${t.id}'),
        points: [LatLng(t.pickupLat!, t.pickupLng!), LatLng(t.dropoffLat!, t.dropoffLng!)],
        color: AppColors.primaryDark.withValues(alpha: 0.55),
        width: 3,
        patterns: [PatternItem.dash(14), PatternItem.gap(8)],
      ));
    }
    return lines;
  }

  Future<void> _openTrip(String tripId) async {
    try {
      final trip = await AdminApi.trip(tripId);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => TripAdminDetailScreen(trip: trip)));
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : 'Could not open this trip.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();
    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('Live Monitoring')), body: body);
  }

  Widget _buildBody() {
    return Column(
      children: [
        _tabBar(),
        Expanded(
          child: switch (_tab) {
            _MonitorTab.drivers => _driversMap(),
            _MonitorTab.riders => _ridersList(),
            _MonitorTab.packages => _packagesList(),
            _MonitorTab.rentals => _rentalsList(),
          },
        ),
      ],
    );
  }

  Widget _tabBar() {
    Widget chip(_MonitorTab tab, String label, int count) {
      final active = _tab == tab;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(count > 0 ? '$label ($count)' : label, style: const TextStyle(fontSize: 12.5)),
          selected: active,
          onSelected: (_) => setState(() => _tab = tab),
          selectedColor: AppColors.primaryContainer,
          backgroundColor: AppColors.surface,
        ),
      );
    }

    final data = _data;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      color: AppColors.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip(_MonitorTab.drivers, 'Drivers', data?.drivers.length ?? 0),
            chip(_MonitorTab.riders, 'Riders', data?.riders.length ?? 0),
            chip(_MonitorTab.packages, 'Packages', data?.packages.length ?? 0),
            chip(_MonitorTab.rentals, 'Rentals', data?.rentals.length ?? 0),
          ],
        ),
      ),
    );
  }

  // ---- Drivers: the interactive map (unchanged behaviour, real GPS pins) ----

  Widget _driversMap() {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: _lagos,
          markers: _markers(),
          polylines: _routes(),
          onTap: (_) => setState(() {
            _selectedDriver = null;
            _selectedTrip = null;
          }),
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
        ),
        if (_loading && _data == null) const Center(child: CircularProgressIndicator()),
        if (_error != null && _data == null)
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.all(24),
              decoration: AppComponents.cardDecoration(),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
                const SizedBox(height: 10),
                ElevatedButton(onPressed: _load, child: const Text('Try again')),
              ]),
            ),
          ),
        Positioned(top: 12, left: 12, right: 12, child: _driverTopBar()),
        if (!_loading && _data != null && _visibleDrivers.isEmpty)
          Positioned(
            top: 76,
            left: 12,
            right: 12,
            child: _infoBanner('No drivers are currently reporting a live location for this filter.'),
          ),
        if (_selectedDriver != null) Positioned(bottom: 16, left: 16, right: 16, child: _driverPanel(_selectedDriver!)),
        if (_selectedTrip != null) Positioned(bottom: 16, left: 16, right: 16, child: _tripPanel(_selectedTrip!)),
      ],
    );
  }

  Widget _infoBanner(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
        ]),
        child: Text(text, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
      );

  Widget _driverTopBar() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
          ]),
          child: TextField(
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Search driver name…',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _StatusFilter.values.map((f) {
              final active = _activeFilters.contains(f);
              final count = (_data?.drivers ?? const []).where((d) => d.markerStatus == f.apiValue).length;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text('${f.label} ($count)', style: const TextStyle(fontSize: 12)),
                  avatar: CircleAvatar(backgroundColor: f.color, radius: 6),
                  selected: active,
                  onSelected: (v) => setState(() {
                    if (v) {
                      _activeFilters.add(f);
                    } else {
                      _activeFilters.remove(f);
                    }
                  }),
                  backgroundColor: AppColors.surface,
                  selectedColor: f.color.withValues(alpha: 0.15),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _driverPanel(LiveMapDriver d) {
    final trip = _selectedDriver?.activeTripId == null
        ? null
        : (_data?.trips ?? const []).where((t) => t.id == _selectedDriver!.activeTripId).firstOrNull;
    final filter = _StatusFilter.values.firstWhere((f) => f.apiValue == d.markerStatus, orElse: () => _StatusFilter.offline);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppComponents.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(d.name.isEmpty ? 'Driver' : d.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              AppComponents.badge(filter.label.toUpperCase(), color: filter.color),
              IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _selectedDriver = null)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _presenceBadge(d.presence),
              const SizedBox(width: 8),
              Text(_timeAgo(d.updatedAt), style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 6),
          Text('Vehicle: ${d.vehicle ?? '—'}   ·   ★ ${d.rating.toStringAsFixed(1)}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          if (trip != null) ...[
            const Divider(height: 20),
            Text('Trip: ${trip.id.length > 8 ? trip.id.substring(0, 8) : trip.id}', style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('Rider: ${trip.riderName.isEmpty ? '—' : trip.riderName}', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            Text('${trip.pickup} → ${trip.destination}', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            Text('Fare: ${Currency.format(trip.fare, decimals: 0)}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DriverDetailScreen(driverId: d.driverId))),
              child: const Text('View driver'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tripPanel(LiveMapTrip t) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppComponents.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(child: Text('Trip ${t.id.length > 8 ? t.id.substring(0, 8) : t.id}', style: const TextStyle(fontWeight: FontWeight.w700))),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _selectedTrip = null)),
          ]),
          Text('${t.pickup} → ${t.destination}', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          Text('Driver: ${t.driverName ?? "Unassigned"}   ·   Rider: ${t.riderName}', style: const TextStyle(fontSize: 12.5)),
          Text('Fare: ${Currency.format(t.fare, decimals: 0)}   ·   ${t.paymentMethod ?? "Not charged"}', style: const TextStyle(fontSize: 12.5)),
        ],
      ),
    );
  }

  // ---- Riders: real active-trip list, real reported position or none ----

  Widget _ridersList() {
    final riders = _data?.riders ?? const [];
    if (_loading && _data == null) return const Center(child: CircularProgressIndicator());
    if (riders.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No riders are currently on an active trip.', style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: riders.length,
        itemBuilder: (context, i) {
          final r = riders[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => _openTrip(r.tripId),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: AppComponents.cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(r.riderName.isEmpty ? 'Rider' : r.riderName, style: const TextStyle(fontWeight: FontWeight.w700))),
                        AppComponents.badge(r.status, color: AppColors.info),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('${r.pickup} → ${r.destination}', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    if (r.driverName != null) Text('Driver: ${r.driverName}', style: const TextStyle(fontSize: 12.5)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _presenceBadge(r.presence),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            r.lat != null && r.lng != null
                                ? '${r.lat!.toStringAsFixed(5)}, ${r.lng!.toStringAsFixed(5)}  ·  ${_timeAgo(r.updatedAt)}'
                                : _timeAgo(r.updatedAt),
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---- Packages: real active deliveries, courier position = driver GPS ----

  Widget _packagesList() {
    final packages = _data?.packages ?? const [];
    if (_loading && _data == null) return const Center(child: CircularProgressIndicator());
    if (packages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No packages are currently in transit.', style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: packages.length,
        itemBuilder: (context, i) {
          final p = packages[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CourierRequestsScreen())),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: AppComponents.cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Package ${p.id.length > 8 ? p.id.substring(0, 8) : p.id}',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        AppComponents.badge(p.status, color: AppColors.warning),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('${p.pickupAddress} → ${p.dropoffAddress}', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    Text('Sender: ${p.senderName}   ·   Recipient: ${p.recipientName}', style: const TextStyle(fontSize: 12.5)),
                    if (p.courierName != null) Text('Courier: ${p.courierName}', style: const TextStyle(fontSize: 12.5)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _presenceBadge(p.presence),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            p.lat != null && p.lng != null
                                ? '${p.lat!.toStringAsFixed(5)}, ${p.lng!.toStringAsFixed(5)}  ·  ${_timeAgo(p.updatedAt)}'
                                : _timeAgo(p.updatedAt),
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---- Rentals: real lifecycle data only — no GPS source exists ----

  Widget _rentalsList() {
    final rentals = _data?.rentals ?? const [];
    if (_loading && _data == null) return const Center(child: CircularProgressIndicator());
    if (rentals.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No rentals are currently active.', style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: rentals.length,
        itemBuilder: (context, i) {
          final r = rentals[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RentalListingsScreen())),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: AppComponents.cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(r.vehicle.isEmpty ? 'Vehicle' : r.vehicle, style: const TextStyle(fontWeight: FontWeight.w700))),
                        AppComponents.badge(r.status, color: AppColors.success),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(r.plateNumber, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 1)),
                    Text('Renter: ${r.renterName}   ·   Owner: ${r.ownerName}', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    Text(
                      '${_formatDate(r.startDate)} → ${_formatDate(r.endDate)}',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Location tracking unavailable — no GPS source for this vehicle.',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
