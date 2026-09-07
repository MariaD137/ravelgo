import 'package:ravelgo_driver_app/services/api_client.dart';

/// A single autocomplete suggestion returned by the backend Places proxy.
class PlaceSuggestion {
  final String placeId;
  final String description;
  PlaceSuggestion({required this.placeId, required this.description});

  factory PlaceSuggestion.fromJson(Map<String, dynamic> j) => PlaceSuggestion(
        placeId: '${j['placeId'] ?? ''}',
        description: '${j['description'] ?? ''}',
      );
}

/// A resolved place: a human-readable address plus its coordinates.
class PlaceLocation {
  final String address;
  final double lat;
  final double lng;
  PlaceLocation({required this.address, required this.lat, required this.lng});

  static double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  factory PlaceLocation.fromJson(Map<String, dynamic> j) => PlaceLocation(
        address: '${j['address'] ?? ''}',
        lat: _d(j['lat']),
        lng: _d(j['lng']),
      );
}

/// Address search, proxied through the RavelGo backend (same endpoints the
/// rider app's ride-booking and "Send a Package" screens already use — see
/// user_app/lib/services/places_api.dart). The backend holds the Google Maps
/// *server* key and calls Google server-side, so no key ever ships to this app.
class PlacesApi {
  /// Address suggestions for a partial query. Returns [] on empty input.
  static Future<List<PlaceSuggestion>> autocomplete(String query, {String? sessionToken}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final buf = StringBuffer('/api/places/autocomplete?q=${Uri.encodeQueryComponent(q)}');
    if (sessionToken != null && sessionToken.isNotEmpty) {
      buf.write('&sessionToken=${Uri.encodeQueryComponent(sessionToken)}');
    }
    final data = await ApiClient.get(buf.toString());
    final list = (data as Map<String, dynamic>)['suggestions'] as List? ?? const [];
    return list.map((e) => PlaceSuggestion.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Resolve a chosen suggestion to an address + coordinates.
  static Future<PlaceLocation> details(String placeId, {String? sessionToken}) async {
    final buf = StringBuffer('/api/places/details?placeId=${Uri.encodeQueryComponent(placeId)}');
    if (sessionToken != null && sessionToken.isNotEmpty) {
      buf.write('&sessionToken=${Uri.encodeQueryComponent(sessionToken)}');
    }
    final data = await ApiClient.get(buf.toString());
    return PlaceLocation.fromJson(data as Map<String, dynamic>);
  }
}
