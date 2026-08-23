import 'package:flutter/material.dart';
import 'package:ravelgo_rider_app/components/LocationService.dart';
import 'package:ravelgo_rider_app/services/ride_session.dart';
import 'package:ravelgo_rider_app/views/TexiModule/SelectRide.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

enum _ActiveField { pickup, destination }

class FindRouteScreen extends StatefulWidget {
  const FindRouteScreen({super.key});

  @override
  _FindRouteScreenState createState() => _FindRouteScreenState();
}

class _FindRouteScreenState extends State<FindRouteScreen> {
  final _pickupController = TextEditingController();
  final _destController = TextEditingController();

  List<dynamic> pickupPlaces = [];
  List<dynamic> dropPlaces = [];
  _ActiveField _activeField = _ActiveField.destination;

  double? _pickupLat;
  double? _pickupLng;

  double? _myLat;
  double? _myLng;
  bool _locatingMe = false;

  @override
  void initState() {
    super.initState();
    // Fetched eagerly (not on tap) so choosing "My Location" as pickup is
    // instant in the common case — a real device position via geolocator,
    // never a hardcoded coordinate.
    _fetchMyLocation();
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _destController.dispose();
    super.dispose();
  }

  Future<void> _fetchMyLocation() async {
    setState(() => _locatingMe = true);
    final position = await LocationService.getCurrentLocation();
    if (!mounted) return;
    setState(() {
      _myLat = position?.latitude;
      _myLng = position?.longitude;
      _locatingMe = false;
    });
  }

  Future<void> _search(String query, {required bool forPickup}) async {
    if (query.isEmpty) {
      setState(() {
        if (forPickup) {
          pickupPlaces = [];
        } else {
          dropPlaces = [];
        }
      });
      return;
    }

    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    final url =
        'https://maps.googleapis.com/maps/api/place/textsearch/json?query=${Uri.encodeComponent(query)}&key=$apiKey';

    try {
      final response = await http.get(Uri.parse(url));
      if (!mounted) return;
      final results = response.statusCode == 200 ? (json.decode(response.body)['results'] as List) : [];
      setState(() {
        if (forPickup) {
          pickupPlaces = results;
        } else {
          dropPlaces = results;
        }
      });
    } catch (_) {
      // No network, a timeout, or a malformed response — fail to an empty
      // result list rather than leaving the widget tree waiting on a
      // request that will never resolve, or throwing uncaught out of this
      // TextField.onChanged handler.
      if (!mounted) return;
      setState(() {
        if (forPickup) {
          pickupPlaces = [];
        } else {
          dropPlaces = [];
        }
      });
    }
  }

  void _choosePickupPlace(Map<String, dynamic> place) {
    final loc = place['geometry']?['location'];
    setState(() {
      _pickupController.text = place['name'] as String? ?? place['formatted_address'] as String? ?? '';
      _pickupLat = (loc?['lat'] as num?)?.toDouble();
      _pickupLng = (loc?['lng'] as num?)?.toDouble();
      pickupPlaces = [];
      _activeField = _ActiveField.destination;
    });
  }

  Future<void> _choosePickupMyLocation() async {
    if (_myLat == null || _myLng == null) {
      await _fetchMyLocation();
    }
    if (!mounted) return;
    if (_myLat == null || _myLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't get your current location. Check location permissions.")),
      );
      return;
    }
    setState(() {
      _pickupController.text = 'My Location';
      _pickupLat = _myLat;
      _pickupLng = _myLng;
      pickupPlaces = [];
      _activeField = _ActiveField.destination;
    });
  }

  void _chooseDestinationPlace(Map<String, dynamic> place) {
    final loc = place['geometry']?['location'];
    final destName = place['name'] as String? ?? place['formatted_address'] as String? ?? '';
    final destLat = (loc?['lat'] as num?)?.toDouble();
    final destLng = (loc?['lng'] as num?)?.toDouble();

    // No pickup chosen yet — default it to the rider's current location
    // rather than blocking the flow on a second explicit tap.
    final pickupName = _pickupController.text.trim().isEmpty ? 'My Location' : _pickupController.text.trim();
    final pickupLat = _pickupController.text.trim().isEmpty ? _myLat : _pickupLat;
    final pickupLng = _pickupController.text.trim().isEmpty ? _myLng : _pickupLng;

    RideSession.instance.setRoute(
      pickup: pickupName,
      destination: destName,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      destLat: destLat,
      destLng: destLng,
    );

    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SelectRide()));
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
            const SizedBox(height: 16),
            Expanded(child: _buildSuggestionsList()),
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
                onChanged: (q) {
                  setState(() => _activeField = _ActiveField.pickup);
                  _search(q, forPickup: true);
                },
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
                controller: _destController,
                style: const TextStyle(fontSize: 14),
                onTap: () => setState(() => _activeField = _ActiveField.destination),
                onChanged: (q) {
                  setState(() => _activeField = _ActiveField.destination);
                  _search(q, forPickup: false);
                },
                decoration: const InputDecoration(
                  hintText: 'Where to?',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestionsList() {
    final isPickup = _activeField == _ActiveField.pickup;
    final results = isPickup ? pickupPlaces : dropPlaces;
    return ListView.builder(
      itemCount: results.length + (isPickup ? 1 : 0),
      itemBuilder: (context, index) {
        if (isPickup && index == 0) {
          return ListTile(
            leading: _locatingMe
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location, color: Colors.black54),
            title: const Text("My Location"),
            onTap: _choosePickupMyLocation,
          );
        }
        final place = results[index - (isPickup ? 1 : 0)] as Map<String, dynamic>;
        return ListTile(
          leading: const Icon(Icons.place),
          title: Text(place['name'] as String? ?? ''),
          subtitle: Text(place['formatted_address'] as String? ?? ''),
          onTap: () => isPickup ? _choosePickupPlace(place) : _chooseDestinationPlace(place),
        );
      },
    );
  }
}
