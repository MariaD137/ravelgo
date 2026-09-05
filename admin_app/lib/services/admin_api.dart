import 'package:ravelgo_admin/services/api_client.dart';

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
int _i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
DateTime _dt(dynamic v) => DateTime.tryParse('$v')?.toLocal() ?? DateTime.now();

String _name(Map? m) {
  if (m == null) return '';
  return [m['firstName'], m['lastName']]
      .where((e) => e != null && '$e'.trim().isNotEmpty)
      .join(' ')
      .trim();
}

class DashboardStats {
  final int activeTrips;
  final int onlineDrivers;
  final int pendingApprovals;
  DashboardStats({required this.activeTrips, required this.onlineDrivers, required this.pendingApprovals});
  factory DashboardStats.fromJson(Map<String, dynamic> j) => DashboardStats(
        activeTrips: _i(j['activeTrips']),
        onlineDrivers: _i(j['onlineDrivers']),
        pendingApprovals: _i(j['pendingApprovals']),
      );
}

class AdminDocument {
  final String id;
  final String title;
  final String status;
  AdminDocument({required this.id, required this.title, required this.status});
  factory AdminDocument.fromJson(Map<String, dynamic> j) =>
      AdminDocument(id: '${j['id']}', title: '${j['title'] ?? ''}', status: '${j['status'] ?? ''}');
}

class AdminDriver {
  final String id;
  // Payout/DriverBankAccount records key off User.id, not this Driver.id —
  // the payouts endpoints need this separate field. See the comment on
  // requireOwnUserId in backend/src/routes/payouts.routes.ts.
  final String userId;
  final String name;
  final String email;
  final String status; // PENDING_REVIEW | ACTIVE | SUSPENDED
  final bool isOnline;
  final double rating;
  final int totalTrips;
  final List<AdminDocument> documents;

  AdminDriver({
    required this.id,
    required this.userId,
    required this.name,
    required this.email,
    required this.status,
    required this.isOnline,
    required this.rating,
    required this.totalTrips,
    required this.documents,
  });

  factory AdminDriver.fromJson(Map<String, dynamic> j) {
    final user = j['user'] as Map?;
    final docs = (j['documents'] as List?) ?? const [];
    return AdminDriver(
      id: '${j['id']}',
      userId: '${user?['id'] ?? j['id']}',
      name: _name(user),
      email: '${user?['email'] ?? ''}',
      status: '${j['status'] ?? 'PENDING_REVIEW'}',
      isOnline: j['isOnline'] == true,
      rating: j['rating'] == null ? 5.0 : _d(j['rating']),
      totalTrips: _i(j['totalTrips']),
      documents: docs.whereType<Map<String, dynamic>>().map(AdminDocument.fromJson).toList(),
    );
  }
}

class AdminRider {
  final String id;
  final String name;
  final String email;
  final bool suspended;
  AdminRider({required this.id, required this.name, required this.email, required this.suspended});
  factory AdminRider.fromJson(Map<String, dynamic> j) => AdminRider(
        id: '${j['id']}',
        name: _name(j),
        email: '${j['email'] ?? ''}',
        suspended: j['suspended'] == true,
      );
}

class AdminRiderTrip {
  final String id;
  final String pickup;
  final String destination;
  final String status;
  final double fare;
  final DateTime requestedAt;
  AdminRiderTrip({
    required this.id,
    required this.pickup,
    required this.destination,
    required this.status,
    required this.fare,
    required this.requestedAt,
  });
  factory AdminRiderTrip.fromJson(Map<String, dynamic> j) => AdminRiderTrip(
        id: '${j['id']}',
        pickup: '${j['pickup'] ?? ''}',
        destination: '${j['destination'] ?? ''}',
        status: '${j['status'] ?? ''}',
        fare: j['finalFare'] == null ? _d(j['estimatedFare']) : _d(j['finalFare']),
        requestedAt: _dt(j['requestedAt']),
      );
}

class AdminRiderDetail {
  final String id;
  final String name;
  final String email;
  final String? phoneNumber;
  final bool suspended;
  final bool isLoyaltyMember;
  final DateTime createdAt;
  final List<AdminRiderTrip> recentTrips;
  AdminRiderDetail({
    required this.id,
    required this.name,
    required this.email,
    required this.phoneNumber,
    required this.suspended,
    required this.isLoyaltyMember,
    required this.createdAt,
    required this.recentTrips,
  });
  factory AdminRiderDetail.fromJson(Map<String, dynamic> j) {
    final trips = (j['ridesAsRider'] as List?) ?? const [];
    return AdminRiderDetail(
      id: '${j['id']}',
      name: _name(j),
      email: '${j['email'] ?? ''}',
      phoneNumber: j['phoneNumber']?.toString(),
      suspended: j['suspended'] == true,
      isLoyaltyMember: j['isLoyaltyMember'] == true,
      createdAt: _dt(j['createdAt']),
      recentTrips: trips.whereType<Map<String, dynamic>>().map(AdminRiderTrip.fromJson).toList(),
    );
  }
}

class AdminTrip {
  final String id;
  final String pickup;
  final String destination;
  final String status;
  final double fare;
  final String riderName;
  final String? driverName;
  final DateTime requestedAt;
  // Only ever populated for an Admin caller (see trips.routes.ts) — null for
  // an unpaid/not-yet-charged trip, not an error.
  final String? paymentStatus;
  final String? paymentMethod;

  AdminTrip({
    required this.id,
    required this.pickup,
    required this.destination,
    required this.status,
    required this.fare,
    required this.riderName,
    required this.driverName,
    required this.requestedAt,
    this.paymentStatus,
    this.paymentMethod,
  });

  factory AdminTrip.fromJson(Map<String, dynamic> j) {
    final driver = j['driver'] as Map?;
    final payment = j['payment'] as Map?;
    return AdminTrip(
      id: '${j['id']}',
      pickup: '${j['pickup'] ?? ''}',
      destination: '${j['destination'] ?? ''}',
      status: '${j['status'] ?? ''}',
      fare: j['finalFare'] == null ? _d(j['estimatedFare']) : _d(j['finalFare']),
      riderName: _name(j['rider'] as Map?),
      driverName: driver == null ? null : (_name(driver['user'] as Map?).isEmpty ? null : _name(driver['user'] as Map?)),
      requestedAt: _dt(j['requestedAt']),
      paymentStatus: payment?['status']?.toString(),
      paymentMethod: payment?['method']?.toString(),
    );
  }
}

class AuditEntry {
  final String id;
  final String actor;
  final String action;
  final String entityType;
  final String? entityId;
  final DateTime createdAt;

  AuditEntry({
    required this.id,
    required this.actor,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.createdAt,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
        id: '${j['id']}',
        actor: '${j['actorEmail'] ?? j['actorSub'] ?? 'admin'}',
        action: '${j['action'] ?? ''}',
        entityType: '${j['entityType'] ?? ''}',
        entityId: j['entityId']?.toString(),
        createdAt: _dt(j['createdAt']),
      );
}

class SupportTicket {
  final String id;
  final String subject;
  final String category;
  final String status;
  final String userName;
  final DateTime createdAt;
  SupportTicket({
    required this.id,
    required this.subject,
    required this.category,
    required this.status,
    required this.userName,
    required this.createdAt,
  });
  factory SupportTicket.fromJson(Map<String, dynamic> j) => SupportTicket(
        id: '${j['id']}',
        subject: '${j['subject'] ?? ''}',
        category: '${j['category'] ?? ''}',
        status: '${j['status'] ?? ''}',
        userName: _name(j['user'] as Map?),
        createdAt: _dt(j['createdAt']),
      );
}

class EmergencyAlert {
  final String id;
  final String type; // SOS | FRAUD_SUSPECTED
  final String status; // OPEN | ACKNOWLEDGED | RESOLVED
  final String? message;
  final String userName;
  final DateTime createdAt;
  EmergencyAlert({
    required this.id,
    required this.type,
    required this.status,
    required this.message,
    required this.userName,
    required this.createdAt,
  });
  factory EmergencyAlert.fromJson(Map<String, dynamic> j) => EmergencyAlert(
        id: '${j['id']}',
        type: '${j['type'] ?? ''}',
        status: '${j['status'] ?? ''}',
        message: j['message']?.toString(),
        userName: _name(j['user'] as Map?),
        createdAt: _dt(j['createdAt']),
      );
}

class CourierRequest {
  final String id;
  final String pickupAddress;
  final String dropoffAddress;
  final String packageDescription;
  final String recipientName;
  final String status;
  final double fare;
  final String senderName;
  final String? driverName;
  final DateTime requestedAt;
  CourierRequest({
    required this.id,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.packageDescription,
    required this.recipientName,
    required this.status,
    required this.fare,
    required this.senderName,
    required this.driverName,
    required this.requestedAt,
  });
  factory CourierRequest.fromJson(Map<String, dynamic> j) {
    final driver = j['driver'] as Map?;
    final dn = driver == null ? '' : _name(driver['user'] as Map?);
    return CourierRequest(
      id: '${j['id']}',
      pickupAddress: '${j['pickupAddress'] ?? ''}',
      dropoffAddress: '${j['dropoffAddress'] ?? ''}',
      packageDescription: '${j['packageDescription'] ?? ''}',
      recipientName: '${j['recipientName'] ?? ''}',
      status: '${j['status'] ?? ''}',
      fare: j['finalFare'] == null ? _d(j['estimatedFare']) : _d(j['finalFare']),
      senderName: _name(j['sender'] as Map?),
      driverName: dn.isEmpty ? null : dn,
      requestedAt: _dt(j['requestedAt']),
    );
  }
}

class CarPaddyRequest {
  final String id;
  final String plateNumber;
  final String status;
  final String driverName;
  final DateTime submittedAt;
  CarPaddyRequest({
    required this.id,
    required this.plateNumber,
    required this.status,
    required this.driverName,
    required this.submittedAt,
  });
  factory CarPaddyRequest.fromJson(Map<String, dynamic> j) {
    final driver = j['driver'] as Map?;
    return CarPaddyRequest(
      id: '${j['id']}',
      plateNumber: '${j['plateNumber'] ?? ''}',
      status: '${j['status'] ?? ''}',
      driverName: driver == null ? '' : _name(driver['user'] as Map?),
      submittedAt: _dt(j['submittedAt']),
    );
  }
}

class StayHost {
  final String firstName;
  final String lastName;
  final String? email;
  StayHost({required this.firstName, required this.lastName, this.email});
  String get name => [firstName, lastName].where((e) => e.trim().isNotEmpty).join(' ').trim();
  factory StayHost.fromJson(Map<String, dynamic> j) => StayHost(
        firstName: '${j['firstName'] ?? ''}',
        lastName: '${j['lastName'] ?? ''}',
        email: j['email']?.toString(),
      );
}

class StayListing {
  final String id;
  final String title;
  final String? description;
  final String address;
  final double pricePerNight;
  final int maxGuests;
  final String status; // PENDING_APPROVAL | APPROVED | REJECTED
  final StayHost? host;
  final int? bookingCount;
  StayListing({
    required this.id,
    required this.title,
    required this.description,
    required this.address,
    required this.pricePerNight,
    required this.maxGuests,
    required this.status,
    required this.host,
    required this.bookingCount,
  });
  factory StayListing.fromJson(Map<String, dynamic> j) => StayListing(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        description: j['description']?.toString(),
        address: '${j['address'] ?? ''}',
        pricePerNight: _d(j['pricePerNight']),
        maxGuests: _i(j['maxGuests']),
        status: '${j['status'] ?? ''}',
        host: j['host'] is Map<String, dynamic> ? StayHost.fromJson(j['host'] as Map<String, dynamic>) : null,
        bookingCount: j['bookingCount'] == null ? null : _i(j['bookingCount']),
      );
}

class StayBooking {
  final String id;
  final DateTime checkIn;
  final DateTime checkOut;
  final int guests;
  final int nights;
  final double totalPrice;
  final String status;
  final String guestName;
  final String? guestEmail;
  StayBooking({
    required this.id,
    required this.checkIn,
    required this.checkOut,
    required this.guests,
    required this.nights,
    required this.totalPrice,
    required this.status,
    required this.guestName,
    required this.guestEmail,
  });
  factory StayBooking.fromJson(Map<String, dynamic> j) {
    final guest = j['guest'] as Map?;
    return StayBooking(
      id: '${j['id']}',
      checkIn: _dt(j['checkIn']),
      checkOut: _dt(j['checkOut']),
      guests: _i(j['guests']),
      nights: _i(j['nights']),
      totalPrice: _d(j['totalPrice']),
      status: '${j['status'] ?? ''}',
      guestName: _name(guest),
      guestEmail: guest?['email']?.toString(),
    );
  }
}

class RentalListing {
  final String id;
  final double dailyRate;
  final String location;
  final String status;
  final String vehicle;
  final String driverName;
  RentalListing({
    required this.id,
    required this.dailyRate,
    required this.location,
    required this.status,
    required this.vehicle,
    required this.driverName,
  });
  factory RentalListing.fromJson(Map<String, dynamic> j) {
    final v = j['vehicle'] as Map?;
    final driver = j['driver'] as Map?;
    final vehicle = v == null ? '' : '${v['brand'] ?? ''} ${v['model'] ?? ''}'.trim();
    return RentalListing(
      id: '${j['id']}',
      dailyRate: _d(j['dailyRate']),
      location: '${j['location'] ?? ''}',
      status: '${j['status'] ?? ''}',
      vehicle: vehicle,
      driverName: driver == null ? '' : _name(driver['user'] as Map?),
    );
  }
}

class SubscriptionPlan {
  final String id;
  final String name;
  final String description;
  final double priceMonthly;
  final bool active;
  SubscriptionPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.priceMonthly,
    required this.active,
  });
  factory SubscriptionPlan.fromJson(Map<String, dynamic> j) => SubscriptionPlan(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        description: '${j['description'] ?? ''}',
        priceMonthly: _d(j['priceMonthly']),
        active: j['active'] != false,
      );
}

class PricingRule {
  final String id;
  final String name;
  final double baseFare;
  final double perKm;
  final double perMinute;
  final bool active;
  PricingRule({
    required this.id,
    required this.name,
    required this.baseFare,
    required this.perKm,
    required this.perMinute,
    required this.active,
  });
  factory PricingRule.fromJson(Map<String, dynamic> j) => PricingRule(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        baseFare: _d(j['baseFare']),
        perKm: _d(j['perKm']),
        perMinute: _d(j['perMinute']),
        active: j['active'] != false,
      );
}

class SurgeZone {
  final String id;
  final String name;
  final String location;
  final double multiplier;
  final bool active;
  SurgeZone({
    required this.id,
    required this.name,
    required this.location,
    required this.multiplier,
    required this.active,
  });
  factory SurgeZone.fromJson(Map<String, dynamic> j) => SurgeZone(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        location: '${j['location'] ?? ''}',
        multiplier: _d(j['multiplier']),
        active: j['active'] != false,
      );
}

class PayoutCalculation {
  final String driverId;
  final double grossAmount;
  final double platformFee;
  final double subscriptionFee;
  final double netAmount;
  final int tripsIncluded;
  final String period;
  PayoutCalculation({
    required this.driverId,
    required this.grossAmount,
    required this.platformFee,
    required this.subscriptionFee,
    required this.netAmount,
    required this.tripsIncluded,
    required this.period,
  });
  factory PayoutCalculation.fromJson(Map<String, dynamic> j) => PayoutCalculation(
        driverId: '${j['driverId']}',
        grossAmount: _d(j['grossAmount']),
        platformFee: _d(j['platformFee']),
        subscriptionFee: _d(j['subscriptionFee']),
        netAmount: _d(j['netAmount']),
        tripsIncluded: _i(j['tripsIncluded']),
        period: '${j['period'] ?? ''}',
      );
}

class AdminPayout {
  final String id;
  final String driverId;
  final String driverName;
  final String driverEmail;
  final double amount;
  final String currency;
  final String status; // PENDING | PROCESSING | COMPLETED | FAILED | CANCELLED
  final String period;
  final String? transactionId;
  final String? failureReason;
  final DateTime? completedAt;
  final DateTime createdAt;
  AdminPayout({
    required this.id,
    required this.driverId,
    required this.driverName,
    required this.driverEmail,
    required this.amount,
    required this.currency,
    required this.status,
    required this.period,
    required this.transactionId,
    required this.failureReason,
    required this.completedAt,
    required this.createdAt,
  });
  factory AdminPayout.fromJson(Map<String, dynamic> j) {
    final driver = j['driver'] as Map?;
    return AdminPayout(
      id: '${j['id']}',
      driverId: '${j['driverId']}',
      driverName: _name(driver),
      driverEmail: '${driver?['email'] ?? ''}',
      amount: _d(j['amount']),
      currency: '${j['currency'] ?? 'USD'}',
      status: '${j['status'] ?? ''}',
      period: '${j['period'] ?? ''}',
      transactionId: j['transactionId']?.toString(),
      failureReason: j['failureReason']?.toString(),
      completedAt: j['completedAt'] == null ? null : _dt(j['completedAt']),
      createdAt: _dt(j['createdAt']),
    );
  }
}

class AdminApi {
  static List _list(dynamic data) => (data is Map ? data['data'] : data) as List? ?? const [];

  static Future<DashboardStats> dashboard() async =>
      DashboardStats.fromJson(await ApiClient.get('/api/admin/dashboard') as Map<String, dynamic>);

  static Future<List<AdminDriver>> drivers() async {
    final data = await ApiClient.get('/api/drivers?pageSize=100');
    return _list(data).whereType<Map<String, dynamic>>().map(AdminDriver.fromJson).toList();
  }

  static Future<AdminDriver> driver(String id) async =>
      AdminDriver.fromJson(await ApiClient.get('/api/drivers/$id') as Map<String, dynamic>);

  static Future<void> setDriverStatus(String id, String status) async {
    await ApiClient.patch('/api/drivers/$id/status', {'status': status});
  }

  static Future<void> reviewDocument(String id, String status) async {
    await ApiClient.patch('/api/documents/$id/review', {'status': status});
  }

  static Future<List<AdminRider>> riders() async {
    final data = await ApiClient.get('/api/riders?pageSize=100');
    return _list(data).whereType<Map<String, dynamic>>().map(AdminRider.fromJson).toList();
  }

  static Future<void> setRiderSuspended(String id, bool suspended) async {
    await ApiClient.patch('/api/riders/$id/status', {'suspended': suspended});
  }

  static Future<AdminRiderDetail> rider(String id) async =>
      AdminRiderDetail.fromJson(await ApiClient.get('/api/riders/$id') as Map<String, dynamic>);

  static Future<List<AdminTrip>> trips() async {
    final data = await ApiClient.get('/api/trips?pageSize=100');
    return _list(data).whereType<Map<String, dynamic>>().map(AdminTrip.fromJson).toList();
  }

  static Future<List<AuditEntry>> audit() async {
    final data = await ApiClient.get('/api/admin/audit?pageSize=100');
    return _list(data).whereType<Map<String, dynamic>>().map(AuditEntry.fromJson).toList();
  }

  // ---- Support tickets ----
  static Future<List<SupportTicket>> supportTickets() async {
    final data = await ApiClient.get('/api/support-tickets?pageSize=100');
    return _list(data).whereType<Map<String, dynamic>>().map(SupportTicket.fromJson).toList();
  }

  static Future<void> setTicketStatus(String id, String status) async {
    await ApiClient.patch('/api/support-tickets/$id/status', {'status': status});
  }

  // ---- Emergency / fraud alerts (same endpoint; screens filter by type) ----
  static Future<List<EmergencyAlert>> alerts() async {
    final data = await ApiClient.get('/api/emergency-alerts?pageSize=100');
    return _list(data).whereType<Map<String, dynamic>>().map(EmergencyAlert.fromJson).toList();
  }

  static Future<void> setAlertStatus(String id, String status) async {
    await ApiClient.patch('/api/emergency-alerts/$id/status', {'status': status});
  }

  // ---- Courier requests ----
  static Future<List<CourierRequest>> courierRequests() async {
    final data = await ApiClient.get('/api/courier-requests?pageSize=100');
    return _list(data).whereType<Map<String, dynamic>>().map(CourierRequest.fromJson).toList();
  }

  static Future<void> setCourierStatus(String id, String status) async {
    await ApiClient.patch('/api/courier-requests/$id/status', {'status': status});
  }

  // ---- Car Paddy requests ----
  static Future<List<CarPaddyRequest>> carPaddyRequests() async {
    final data = await ApiClient.get('/api/car-paddy?pageSize=100');
    return _list(data).whereType<Map<String, dynamic>>().map(CarPaddyRequest.fromJson).toList();
  }

  static Future<void> reviewCarPaddy(String id, String status) async {
    await ApiClient.patch('/api/car-paddy/$id', {'status': status});
  }

  // ---- Rental listings ----
  static Future<List<RentalListing>> rentals() async {
    final data = await ApiClient.get('/api/rentals?pageSize=100');
    return _list(data).whereType<Map<String, dynamic>>().map(RentalListing.fromJson).toList();
  }

  static Future<void> setRentalStatus(String id, String status) async {
    await ApiClient.patch('/api/rentals/$id/status', {'status': status});
  }

  // ---- Short Stays (property listings) ----
  static Future<List<StayListing>> stays() async {
    final data = await ApiClient.get('/api/stays?pageSize=100');
    return _list(data).whereType<Map<String, dynamic>>().map(StayListing.fromJson).toList();
  }

  static Future<StayListing> stay(String id) async =>
      StayListing.fromJson(await ApiClient.get('/api/stays/$id') as Map<String, dynamic>);

  static Future<void> setStayStatus(String id, String status) async {
    await ApiClient.patch('/api/stays/$id/status', {'status': status});
  }

  static Future<List<StayBooking>> stayBookings(String id) async {
    final data = await ApiClient.get('/api/stays/$id/bookings');
    return (data as List).whereType<Map<String, dynamic>>().map(StayBooking.fromJson).toList();
  }

  // ---- Payouts ----
  static Future<List<AdminPayout>> payouts({String? status}) async {
    final query = status == null ? '' : '&status=$status';
    final data = await ApiClient.get('/api/payouts?pageSize=100$query');
    return _list(data).whereType<Map<String, dynamic>>().map(AdminPayout.fromJson).toList();
  }

  static Future<PayoutCalculation> calculatePayout(String driverId, String period) async {
    final data = await ApiClient.post('/api/payouts/calculate', {'driverId': driverId, 'period': period});
    return PayoutCalculation.fromJson(data as Map<String, dynamic>);
  }

  static Future<AdminPayout> createPayout(String driverId, String period, {double? amount}) async {
    final data = await ApiClient.post('/api/payouts/create', {
      'driverId': driverId,
      'period': period,
      if (amount != null) 'amount': amount,
    });
    return AdminPayout.fromJson(data as Map<String, dynamic>);
  }

  static Future<AdminPayout> processPayout(String id) async {
    final data = await ApiClient.post('/api/payouts/$id/process');
    return AdminPayout.fromJson(data as Map<String, dynamic>);
  }

  static Future<AdminPayout> completePayout(String id, {String? transactionId}) async {
    final data = await ApiClient.post('/api/payouts/$id/complete', {
      if (transactionId != null && transactionId.isNotEmpty) 'transactionId': transactionId,
    });
    return AdminPayout.fromJson(data as Map<String, dynamic>);
  }

  static Future<AdminPayout> failPayout(String id, String reason) async {
    final data = await ApiClient.post('/api/payouts/$id/fail', {'failureReason': reason});
    return AdminPayout.fromJson(data as Map<String, dynamic>);
  }

  // ---- Subscription plans ----
  static Future<List<SubscriptionPlan>> subscriptionPlans() async {
    final data = await ApiClient.get('/api/subscription-plans');
    return _list(data).whereType<Map<String, dynamic>>().map(SubscriptionPlan.fromJson).toList();
  }

  // ---- Pricing rules (real backend, admin-only writes) ----
  static Future<List<PricingRule>> pricingRules() async {
    final data = await ApiClient.get('/api/pricing-rules');
    return _list(data).whereType<Map<String, dynamic>>().map(PricingRule.fromJson).toList();
  }

  static Future<PricingRule> createPricingRule({
    required String name,
    required double baseFare,
    required double perKm,
    required double perMinute,
  }) async {
    final data = await ApiClient.post('/api/pricing-rules', {
      'name': name,
      'baseFare': baseFare,
      'perKm': perKm,
      'perMinute': perMinute,
    });
    return PricingRule.fromJson(data as Map<String, dynamic>);
  }

  static Future<PricingRule> updatePricingRule(
    String id, {
    String? name,
    double? baseFare,
    double? perKm,
    double? perMinute,
    bool? active,
  }) async {
    final data = await ApiClient.patch('/api/pricing-rules/$id', {
      if (name != null) 'name': name,
      if (baseFare != null) 'baseFare': baseFare,
      if (perKm != null) 'perKm': perKm,
      if (perMinute != null) 'perMinute': perMinute,
      if (active != null) 'active': active,
    });
    return PricingRule.fromJson(data as Map<String, dynamic>);
  }

  // ---- Surge zones (real backend, admin-only writes) ----
  static Future<List<SurgeZone>> surgeZones() async {
    final data = await ApiClient.get('/api/surge-zones');
    return _list(data).whereType<Map<String, dynamic>>().map(SurgeZone.fromJson).toList();
  }

  static Future<SurgeZone> createSurgeZone({
    required String name,
    required String location,
    required double multiplier,
  }) async {
    final data = await ApiClient.post('/api/surge-zones', {
      'name': name,
      'location': location,
      'multiplier': multiplier,
    });
    return SurgeZone.fromJson(data as Map<String, dynamic>);
  }

  static Future<SurgeZone> updateSurgeZone(
    String id, {
    double? multiplier,
    bool? active,
  }) async {
    final data = await ApiClient.patch('/api/surge-zones/$id', {
      if (multiplier != null) 'multiplier': multiplier,
      if (active != null) 'active': active,
    });
    return SurgeZone.fromJson(data as Map<String, dynamic>);
  }
}
