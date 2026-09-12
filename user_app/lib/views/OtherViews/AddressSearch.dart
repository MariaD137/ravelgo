import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/Model/app_state.dart';
import 'package:ravelgo_user_app/components/LocationService.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Search and pick a saved address (Home / Work).
///
/// Selecting a result saves it into RiderAppState, which persists it
/// on-device (see Model/app_state.dart) and returns it to the calling
/// screen via Navigator.pop. The suggestion list is demo data — a
/// different, real Places-backed search already exists for booking a ride
/// (PlaceSearchScreen/PlacesApi) but this saved-address flow doesn't use it
/// yet.
///
/// LOCATION: "use current location" retrieves real device coordinates via
/// LocationService (geolocator). No geocoding service is connected, so the
/// saved value is the real coordinate pair, not a fabricated street address.
class AddressSearch extends StatefulWidget {
  final String addressType; // "Home" or "Work"

  const AddressSearch({super.key, required this.addressType});

  @override
  State<AddressSearch> createState() => _AddressSearchState();
}

class _AddressSearchState extends State<AddressSearch> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  static const List<String> _suggestions = [
    'Denco court 1, Kusenla Road, Lekki',
    'Ikeja City Mall, Alausa, Ikeja',
    'Victoria Island, Lagos',
    'Maryland Mall, Ikorodu Road',
    'Lekki Phase 1, Admiralty Way',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _results {
    var list = _suggestions.where((s) => s.toLowerCase().contains(_query)).toList();
    if (_query.isNotEmpty && list.isEmpty) {
      // Let the user save exactly what they typed when nothing matches.
      list = [_searchController.text.trim()];
    }
    return list;
  }

  void _select(String address) {
    RiderAppState.instance.saveAddress(widget.addressType, address);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${widget.addressType} address saved')),
    );
    Navigator.pop(context, address);
  }

  bool _locating = false;

  Future<void> _useCurrentLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    final position = await LocationService.getCurrentLocation();
    if (!mounted) return;
    setState(() => _locating = false);
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not get your location - check location permissions and try again.'),
      ));
      return;
    }
    // Real coordinates; a geocoding service would turn these into a street
    // address once connected.
    final address =
        'Current location (${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)})';
    _select(address);
  }

  @override
  Widget build(BuildContext context) {
    final saved = RiderAppState.instance.savedAddresses[widget.addressType];
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: const BackButton(color: AppColors.textPrimary),
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        title: Text('${widget.addressType} address', style: const TextStyle(color: AppColors.textPrimary)),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            _buildSearchBar(),
            const SizedBox(height: 20),
            if (saved != null) ...[
              const Text('Current', style: TextStyle(fontWeight: FontWeight.w700)),
              _buildLocationTile(
                icon: widget.addressType == 'Home' ? Icons.home : Icons.work_outline,
                title: saved,
                subtitle: 'Saved ${widget.addressType.toLowerCase()} address',
                onTap: () => _select(saved),
              ),
              const Divider(),
            ],
            _buildLocationTile(
              icon: Icons.my_location_outlined,
              title: _locating ? 'Getting your location...' : 'Use my current location',
              subtitle: '',
              onTap: _useCurrentLocation,
            ),
            const Divider(),
            Expanded(
              child: ListView(
                children: _results
                    .map((location) => _buildLocationTile(
                          icon: Icons.location_on_outlined,
                          title: location,
                          subtitle: 'Lagos, Nigeria',
                          onTap: () => _select(location),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.primary),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          const Icon(Icons.search, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search for an address',
                border: InputBorder.none,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.my_location_outlined, color: AppColors.textSecondary),
            onPressed: _useCurrentLocation,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.textPrimary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle.isNotEmpty
          ? Text(subtitle, style: const TextStyle(color: AppColors.textSecondary))
          : null,
      onTap: onTap,
    );
  }
}
