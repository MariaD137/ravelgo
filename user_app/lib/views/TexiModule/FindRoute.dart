import 'package:flutter/material.dart';
import 'package:ravelgo_driver/views/TexiModule/SelectRide.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';


class FindRouteScreen extends StatefulWidget {
  @override
  _FindRouteScreenState createState() => _FindRouteScreenState();
}

class _FindRouteScreenState extends State<FindRouteScreen> {

  List<dynamic> pickupPlaces = [];
  List<dynamic> dropPlaces = [];

  void _onTextChangedPickup(String query) async {
    if (query.isEmpty) {
      setState(() => pickupPlaces = []);
      return;
    }

    final apiKey = dotenv.env['GOOGLE_API_KEY'];
    final url =
        'https://maps.googleapis.com/maps/api/place/textsearch/json?query=${Uri.encodeComponent(query)}&key=$apiKey';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() => pickupPlaces = data['results']);
    } else {
      print('Failed to fetch places');
    }
  }
  void _onTextChangedDrop(String query) async {
    if (query.isEmpty) {
      setState(() => dropPlaces = []);
      return;
    }

    final apiKey = dotenv.env['GOOGLE_API_KEY'];
    final url =
        'https://maps.googleapis.com/maps/api/place/textsearch/json?query=${Uri.encodeComponent(query)}&key=$apiKey';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() => dropPlaces = data['results']);
    } else {
      print('Failed to fetch places');
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close,color: Colors.black,),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Your route', style: TextStyle(color: Colors.black)),
        centerTitle: true,
      ),
      body:
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            _buildRouteInputs(),
            const SizedBox(height: 16),
            _buildSearchField(),
            const SizedBox(height: 16),
            // _buildMyLocation(),
            // const SizedBox(height: 16),
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
              dense: true, // Makes ListTile more compact vertically
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: const Icon(Icons.radio_button_checked, color: Colors.green, size: 20),
              title: TextField(
                style: const TextStyle(fontSize: 14),
                onChanged: _onTextChangedPickup,
                decoration: const InputDecoration(
                  hintText: 'Your Location',
                  border: InputBorder.none,
                  isDense: true, // Reduce internal padding
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8), // spacing between tile and icon
        const Icon(Icons.add, color: Colors.black),
      ],
    );
  }
  //
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
              dense: true, // Makes ListTile more compact vertically
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: const Icon(Icons.search, color: Colors.black, size: 20),
              title: TextField(
                style: const TextStyle(fontSize: 14),
                onChanged: _onTextChangedDrop,
                decoration: const InputDecoration(
                  hintText: 'Lekki',
                  border: InputBorder.none,
                  isDense: true, // Reduce internal padding
                  contentPadding: EdgeInsets.zero,

                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8), // spacing between tile and icon
        const Icon(Icons.swap_vert, size: 26),
      ],
    );
  }

  Widget _buildMyLocation() {
    return Row(
      children: const [
        Icon(Icons.home, color: Colors.black54),
        SizedBox(width: 8),
        Text('My location', style: TextStyle(fontSize: 16)),
      ],
    );
  }

  Widget _buildRecentPlacesList() {
    return ListView.builder(
        itemCount: pickupPlaces.length + 1, // +1 for "My Location"
        itemBuilder: (context, index) {

          if (index == 0) {
            return ListTile(
              leading: const Icon(Icons.home, color: Colors.black54),
              title: Text("My Location"),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => SelectRide()),
                );
              },
            );
          } else {
            final place = pickupPlaces[index - 1]; // Offset by -1
            return ListTile(
              leading: Icon(Icons.place),
              title: Text(place['name']),
              subtitle: Text(place['formatted_address']),
              onTap: () {
                // Handle place selection
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => SelectRide()),
                );
              },
            );
          }
      },
    );
  }
}