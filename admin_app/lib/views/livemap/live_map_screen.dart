import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

/// The operations Live Map: every pin is a driver who has actually reported a
/// coordinate to the backend (GET /api/admin/live-map) — a driver who hasn't
/// simply isn't drawn, rather than being given a fabricated position. Polls
/// every 8s (there's no push feed for this yet — see docs/realtime-architecture.md)
/// so it stays close to real-time without needing a new websocket fan-out.
class LiveMapScreen extends StatefulWidget {
  final bool embedded;
  const LiveMapScreen({super.key, this.embedded = false});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

const _lagos = CameraPosition(target: LatLng(6.5244, 3.3792), zoom: 11);

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

class _LiveMapScreenState extends State<LiveMapScreen> {
  Timer? _poll;
  bool _loading = true;
  String? _error;
  LiveMapData? _data;
  LiveMapDriver? _selectedDriver;
  LiveMapTrip? _selectedTrip;
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

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();
    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('Live Map')), body: body);
  }

  Widget _buildBody() {
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
        Positioned(top: 12, left: 12, right: 12, child: _topBar()),
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

  Widget _topBar() {
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
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
