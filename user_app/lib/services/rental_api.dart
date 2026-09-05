import 'package:ravelgo_user_app/services/api_client.dart';

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
int _i(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;

class RentalVehicle {
  final String brand;
  final String model;
  final String colour;
  final String plateNumber;
  final String year;

  RentalVehicle({required this.brand, required this.model, required this.colour, required this.plateNumber, required this.year});

  String get label => '$brand $model'.trim();

  factory RentalVehicle.fromJson(Map<String, dynamic> j) => RentalVehicle(
        brand: '${j['brand'] ?? ''}',
        model: '${j['model'] ?? ''}',
        colour: '${j['colour'] ?? ''}',
        plateNumber: '${j['plateNumber'] ?? ''}',
        year: '${j['year'] ?? ''}',
      );
}

/// A vehicle listed for rental by a driver, as browsed by a customer. Backed
/// by the real GET /api/rentals endpoint — no hardcoded cars.
class RentalListing {
  final String id;
  final double dailyRate;
  final String location;
  final String status;
  final RentalVehicle? vehicle;

  RentalListing({required this.id, required this.dailyRate, required this.location, required this.status, this.vehicle});

  factory RentalListing.fromJson(Map<String, dynamic> j) => RentalListing(
        id: '${j['id']}',
        dailyRate: _d(j['dailyRate']),
        location: '${j['location'] ?? ''}',
        status: '${j['status'] ?? ''}',
        vehicle: j['vehicle'] is Map<String, dynamic> ? RentalVehicle.fromJson(j['vehicle'] as Map<String, dynamic>) : null,
      );
}

/// A customer's reservation of a [RentalListing]. `status`/`paymentStatus`
/// mirror the backend's RentalBookingStatus/PaymentStatus enums.
class RentalBooking {
  final String id;
  final String startDate;
  final String endDate;
  final int days;
  final double totalPrice;
  final String status; // PENDING_PAYMENT | CONFIRMED | CANCELLED | COMPLETED
  final String paymentStatus; // PENDING | SUCCEEDED | FAILED | REFUNDED
  final RentalListing? listing;

  RentalBooking({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.days,
    required this.totalPrice,
    required this.status,
    required this.paymentStatus,
    this.listing,
  });

  factory RentalBooking.fromJson(Map<String, dynamic> j) => RentalBooking(
        id: '${j['id']}',
        startDate: '${j['startDate'] ?? ''}',
        endDate: '${j['endDate'] ?? ''}',
        days: _i(j['days']),
        totalPrice: _d(j['totalPrice']),
        status: '${j['status'] ?? ''}',
        paymentStatus: '${j['paymentStatus'] ?? ''}',
        listing: j['listing'] is Map<String, dynamic> ? RentalListing.fromJson(j['listing'] as Map<String, dynamic>) : null,
      );
}

/// Car rental, proxied through the RavelGo backend. Price is always
/// recomputed server-side from the listing's current dailyRate and the
/// requested date range — this client only sends the dates.
class RentalApi {
  static Future<List<RentalListing>> browse() async {
    final data = await ApiClient.get('/api/rentals?page=1&pageSize=50');
    final items = (data as Map<String, dynamic>)['data'] as List? ?? const [];
    return items.map((e) => RentalListing.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<RentalListing> listing(String id) async {
    final data = await ApiClient.get('/api/rentals/$id');
    return RentalListing.fromJson(data as Map<String, dynamic>);
  }

  static Future<RentalBooking> book({
    required String listingId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final data = await ApiClient.post('/api/rentals/$listingId/book', {
      'startDate': startDate.toUtc().toIso8601String(),
      'endDate': endDate.toUtc().toIso8601String(),
    });
    return RentalBooking.fromJson(data as Map<String, dynamic>);
  }

  /// Pay for a booking by CARD. The backend creates a Stripe PaymentIntent and
  /// returns its clientSecret, which the app confirms via the PaymentSheet.
  static Future<String> payWithCard(String bookingId) async {
    final data = await ApiClient.post('/api/rental-bookings/$bookingId/pay', {'method': 'CARD'});
    final m = data as Map<String, dynamic>;
    final secret = m['clientSecret'];
    if (secret == null || '$secret'.isEmpty) {
      throw Exception('Card payment could not be started.');
    }
    return '$secret';
  }

  /// Pay for a booking from the customer's RavelGo Cash balance. Settles
  /// immediately on the backend; throws on insufficient funds (402).
  static Future<RentalBooking> payWithWallet(String bookingId) async {
    final data = await ApiClient.post('/api/rental-bookings/$bookingId/pay', {'method': 'WALLET'});
    return RentalBooking.fromJson(data as Map<String, dynamic>);
  }

  static Future<List<RentalBooking>> myBookings() async {
    final data = await ApiClient.get('/api/rental-bookings/mine');
    return ((data as List?) ?? const []).map((e) => RentalBooking.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<RentalBooking> booking(String id) async {
    final data = await ApiClient.get('/api/rental-bookings/$id');
    return RentalBooking.fromJson(data as Map<String, dynamic>);
  }

  static Future<RentalBooking> cancel(String id) async {
    final data = await ApiClient.patch('/api/rental-bookings/$id/cancel');
    return RentalBooking.fromJson(data as Map<String, dynamic>);
  }
}
