import 'package:ravelgo_user_app/services/api_client.dart';

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
int _i(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;

class PropertyListing {
  final String id;
  final String title;
  final String? description;
  final String address;
  final String? imageUrl;
  final double pricePerNight;
  final int maxGuests;
  final String status;
  PropertyListing({
    required this.id,
    required this.title,
    this.description,
    required this.address,
    this.imageUrl,
    required this.pricePerNight,
    required this.maxGuests,
    required this.status,
  });

  factory PropertyListing.fromJson(Map<String, dynamic> j) => PropertyListing(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        description: j['description']?.toString(),
        address: '${j['address'] ?? ''}',
        imageUrl: j['imageUrl']?.toString(),
        pricePerNight: _d(j['pricePerNight']),
        maxGuests: _i(j['maxGuests']),
        status: '${j['status'] ?? ''}',
      );
}

class StayBooking {
  final String id;
  final String checkIn;
  final String checkOut;
  final int guests;
  final int nights;
  final double totalPrice;
  final String status;
  final PropertyListing? property;
  StayBooking({
    required this.id,
    required this.checkIn,
    required this.checkOut,
    required this.guests,
    required this.nights,
    required this.totalPrice,
    required this.status,
    this.property,
  });

  factory StayBooking.fromJson(Map<String, dynamic> j) => StayBooking(
        id: '${j['id']}',
        checkIn: '${j['checkIn'] ?? ''}',
        checkOut: '${j['checkOut'] ?? ''}',
        guests: _i(j['guests']),
        nights: _i(j['nights']),
        totalPrice: _d(j['totalPrice']),
        status: '${j['status'] ?? ''}',
        property: j['property'] is Map<String, dynamic>
            ? PropertyListing.fromJson(j['property'] as Map<String, dynamic>)
            : null,
      );
}

/// Short-stay property rentals, proxied through the RavelGo backend. Booking
/// price is always recomputed server-side from the listing's current
/// pricePerNight — this client only sends the requested dates and guest count.
class StaysApi {
  static Future<List<PropertyListing>> browse() async {
    final data = await ApiClient.get('/api/stays?page=1&pageSize=50');
    final items = (data as Map<String, dynamic>)['data'] as List? ?? const [];
    return items.map((e) => PropertyListing.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<PropertyListing> listing(String id) async {
    final data = await ApiClient.get('/api/stays/$id');
    return PropertyListing.fromJson(data as Map<String, dynamic>);
  }

  static Future<StayBooking> book({
    required String propertyId,
    required DateTime checkIn,
    required DateTime checkOut,
    required int guests,
  }) async {
    final data = await ApiClient.post('/api/stays/$propertyId/book', {
      'checkIn': checkIn.toUtc().toIso8601String(),
      'checkOut': checkOut.toUtc().toIso8601String(),
      'guests': guests,
    });
    return StayBooking.fromJson(data as Map<String, dynamic>);
  }

  static Future<List<StayBooking>> myBookings() async {
    final data = await ApiClient.get('/api/stays/bookings/mine');
    return ((data as List?) ?? const [])
        .map((e) => StayBooking.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
