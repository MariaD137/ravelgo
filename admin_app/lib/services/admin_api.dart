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
  final String name;
  final String email;
  final String status; // PENDING_REVIEW | ACTIVE | SUSPENDED
  final bool isOnline;
  final double rating;
  final int totalTrips;
  final List<AdminDocument> documents;

  AdminDriver({
    required this.id,
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

class AdminTrip {
  final String id;
  final String pickup;
  final String destination;
  final String status;
  final double fare;
  final String riderName;
  final String? driverName;
  final DateTime requestedAt;

  AdminTrip({
    required this.id,
    required this.pickup,
    required this.destination,
    required this.status,
    required this.fare,
    required this.riderName,
    required this.driverName,
    required this.requestedAt,
  });

  factory AdminTrip.fromJson(Map<String, dynamic> j) {
    final driver = j['driver'] as Map?;
    return AdminTrip(
      id: '${j['id']}',
      pickup: '${j['pickup'] ?? ''}',
      destination: '${j['destination'] ?? ''}',
      status: '${j['status'] ?? ''}',
      fare: j['finalFare'] == null ? _d(j['estimatedFare']) : _d(j['finalFare']),
      riderName: _name(j['rider'] as Map?),
      driverName: driver == null ? null : (_name(driver['user'] as Map?).isEmpty ? null : _name(driver['user'] as Map?)),
      requestedAt: _dt(j['requestedAt']),
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

  // ---- Subscription plans ----
  static Future<List<SubscriptionPlan>> subscriptionPlans() async {
    final data = await ApiClient.get('/api/subscription-plans');
    return _list(data).whereType<Map<String, dynamic>>().map(SubscriptionPlan.fromJson).toList();
  }
}
