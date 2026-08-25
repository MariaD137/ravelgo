import 'package:flutter/material.dart';
import 'package:ravelgo_user/views/TexiModule/select_ride.dart';
import 'package:ravelgo_user/components/location_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

enum _ActiveField { pickup, drop }

class FindRouteScreen extends StatefulWidget {
  const FindRouteScreen({super.key});

  @override
  State createState() => _FindRouteScreenState();
}

class _FindRouteScreenState extends State<FindRouteScreen> {
  final _pickupController = TextEditingController();
  final _dropController = TextEditingController();

  List<dynamic> pickupPlaces = [];
  List<dynamic> dropPlaces = [];
  _ActiveField _activeField = _ActiveField.pickup;
  bool _locatingMe = false;
  String? _locationError;

  @override
  void dispose() {
    _pickupController.dispose();
    _dropController.dispose();
    super.dispose();
  }

  void _onTextChangedPickup(String query) async {
    setState(() {
      _activeField = _ActiveField.pickup;
      _locationError = null;
    });
    if (query.isEmpty) {
      setState(() => pickupPlaces = []);
      return;
    }
    final results = await _searchPlaces(query);
    if (mounted) setState(() => pickupPlaces = results);
  }

  void _onTextChangedDrop(String query) async {
    setState(() => _activeField = _ActiveField.drop);
    if (query.isEmpty) {
      setState(() => dropPlaces = []);
      return;
    }
    final results = await _searchPlaces(query);
    if (mounted) setState(() => dropPlaces = results);
  }

  Future<List<dynamic>> _searchPlaces(String query) async {
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    final url =
        'https://maps.googleapis.com/maps/api/place/textsearch/json?query=${Uri.encodeComponent(query)}&key=$apiKey';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return (data['results'] as List?) ?? [];
      }
    } catch (_) {
      // Network/parse failure — leave the results list unchanged rather
      // than surfacing a raw exception while the rider is still typing.
    }
    return [];
  }

  Future<void> _useMyLocation() async {
    setState(() {
      _locatingMe = true;
      _locationError = null;
    });
    final position = await LocationService.getCurrentLocation();
    if (position == null) {
      if (!mounted) return;
      setState(() {
        _locatingMe = false;
        _locationError = "Couldn't get your location. Check location permissions and try again.";
      });
      return;
    }

    String address = 'My current location';
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    try {
      final url = 'https://maps.googleapis.com/maps/api/geocode/json'
          '?latlng=${position.latitude},${position.longitude}&key=$apiKey';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          address = results.first['formatted_address'] as String? ?? address;
        }
      }
    } catch (_) {
      // Fall back to the plain "My current location" label below.
    }

    if (!mounted) return;
    setState(() {
      _locatingMe = false;
      _pickupController.text = address;
      pickupPlaces = [];
      _activeField = _ActiveField.drop;
    });
  }

  void _selectPlace(Map<String, dynamic> place) {
    final address = (place['formatted_address'] ?? place['name'] ?? '').toString();
    if (_activeField == _ActiveField.pickup) {
      setState(() {
        _pickupController.text = address;
        pickupPlaces = [];
        _activeField = _ActiveField.drop;
      });
      return;
    }

    setState(() {
      _dropController.text = address;
      dropPlaces = [];
    });
    _tryContinue();
  }

  void _tryContinue() {
    final pickup = _pickupController.text.trim();
    final destination = _dropController.text.trim();
    if (pickup.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set a pickup location first')),
      );
      setState(() => _activeField = _ActiveField.pickup);
      return;
    }
    if (destination.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => SelectRide(pickup: pickup, destination: destination)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Your route', style: TextStyle(color: Colors.black)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            _buildRouteInputs(),
            const SizedBox(height: 16),
            _buildSearchField(),
            if (_locationError != null) ...[
              const SizedBox(height: 8),
              Text(_locationError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            Expanded(child: _buildRecentPlacesList()),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteInputs() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black26),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: const Icon(Icons.radio_button_checked, color: Colors.green, size: 20),
              title: TextField(
                controller: _pickupController,
                style: const TextStyle(fontSize: 14),
                onTap: () => setState(() => _activeField = _ActiveField.pickup),
                onChanged: _onTextChangedPickup,
                decoration: const InputDecoration(
                  hintText: 'Your Location',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.add, color: Colors.black),
      ],
    );
  }

  Widget _buildSearchField() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black26),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: const Icon(Icons.search, color: Colors.black, size: 20),
              title: TextField(
                controller: _dropController,
                style: const TextStyle(fontSize: 14),
                onTap: () => setState(() => _activeField = _ActiveField.drop),
                onChanged: _onTextChangedDrop,
                decoration: const InputDecoration(
                  hintText: 'Lekki',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.swap_vert, size: 26),
      ],
    );
  }

  Widget _buildRecentPlacesList() {
    final places = _activeField == _ActiveField.pickup ? pickupPlaces : dropPlaces;
    final showMyLocation = _activeField == _ActiveField.pickup;

    return ListView.builder(
      itemCount: places.length + (showMyLocation ? 1 : 0),
      itemBuilder: (context, index) {
        if (showMyLocation && index == 0) {
          return ListTile(
            leading: _locatingMe
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.home, color: Colors.black54),
            title: const Text("My Location"),
            onTap: _locatingMe ? null : _useMyLocation,
          );
        }
        final place = places[index - (showMyLocation ? 1 : 0)] as Map<String, dynamic>;
        return ListTile(
          leading: const Icon(Icons.place),
          title: Text(place['name']?.toString() ?? ''),
          subtitle: Text(place['formatted_address']?.toString() ?? ''),
          onTap: () => _selectPlace(place),
        );
      },
    );
  }
}
