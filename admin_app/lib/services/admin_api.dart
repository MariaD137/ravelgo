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
  final int driversOnTrip;
  final int availableDrivers;
  // Pending DOCUMENT + Car Paddy reviews. NOT the number of drivers waiting
  // for an approval decision — see pendingDriverApplications.
  final int pendingApprovals;
  // Drivers whose Driver.status is still PENDING_REVIEW: the real approval
  // queue, i.e. the ones the "Approve driver" action on the detail screen
  // hasn't been taken for yet.
  final int pendingDriverApplications;
  final int pendingRideRequests;
  final int activeLogisticsDeliveries;
  final int registeredRiders;
  final double cashCollectedToday;
  final double cardRevenueToday;
  final double walletRevenueToday;
  DashboardStats({
    required this.activeTrips,
    required this.onlineDrivers,
    required this.driversOnTrip,
    required this.availableDrivers,
    required this.pendingApprovals,
    required this.pendingDriverApplications,
    required this.pendingRideRequests,
    required this.activeLogisticsDeliveries,
    required this.registeredRiders,
    required this.cashCollectedToday,
    required this.cardRevenueToday,
    required this.walletRevenueToday,
  });
  factory DashboardStats.fromJson(Map<String, dynamic> j) => DashboardStats(
        activeTrips: _i(j['activeTrips']),
        onlineDrivers: _i(j['onlineDrivers']),
        driversOnTrip: _i(j['driversOnTrip']),
        availableDrivers: _i(j['availableDrivers']),
        pendingApprovals: _i(j['pendingApprovals']),
        pendingDriverApplications: _i(j['pendingDriverApplications']),
        pendingRideRequests: _i(j['pendingRideRequests']),
        activeLogisticsDeliveries: _i(j['activeLogisticsDeliveries']),
        registeredRiders: _i(j['registeredRiders']),
        cashCollectedToday: _d(j['cashCollectedToday']),
        cardRevenueToday: _d(j['cardRevenueToday']),
        walletRevenueToday: _d(j['walletRevenueToday']),
      );
}

class AdminDocument {
  final String id;
  final String title;
  final String status;
  // The private S3 object key — never a usable URL on its own. A fresh
  // signed URL is fetched on demand via AdminApi.documentSignedUrl.
  final String? fileKey;
  final DateTime? expiryDate;
  // Only ever populated when status is REJECTED; cleared server-side on
  // approval.
  final String? rejectionReason;
  AdminDocument({
    required this.id,
    required this.title,
    required this.status,
    this.fileKey,
    this.expiryDate,
    this.rejectionReason,
  });
  factory AdminDocument.fromJson(Map<String, dynamic> j) => AdminDocument(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        status: '${j['status'] ?? ''}',
        fileKey: j['fileKey']?.toString(),
        expiryDate: j['expiryDate'] == null ? null : DateTime.tryParse('${j['expiryDate']}')?.toLocal(),
        rejectionReason: j['rejectionReason']?.toString(),
      );
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
  // Never a literal null/undefined string — display "Not provided" when this
  // is null, rather than inventing a value.
  final String? phoneNumber;
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
    required this.phoneNumber,
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
      // Never default a missing status to a real review outcome.
      status: '${j['status'] ?? ''}',
      isOnline: j['isOnline'] == true,
      rating: j['rating'] == null ? 5.0 : _d(j['rating']),
      totalTrips: _i(j['totalTrips']),
      phoneNumber: user?['phoneNumber']?.toString(),
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

class AnalyticsDay {
  final String date; // YYYY-MM-DD
  final double revenue;
  final int completedTrips;
  AnalyticsDay({required this.date, required this.revenue, required this.completedTrips});
  factory AnalyticsDay.fromJson(Map<String, dynamic> j) => AnalyticsDay(
        date: '${j['date'] ?? ''}',
        revenue: _d(j['revenue']),
        completedTrips: _i(j['completedTrips']),
      );
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

/// One service's marketplace commission rate (backend `CommissionConfig`
/// table) — the DB-driven replacement for the old hardcoded
/// PLATFORM_COMMISSION_RATE constant. Writable by a Super Admin only
/// ("settings:write"); every Admin preset can read it.
/// Cancellation/waiting/surge-band/package-surcharge policy — the single
/// PricingPolicy row (backend/src/lib/pricing-policy.ts). Read is open to
/// any Admin preset; PATCH /admin/pricing-policy is Super Admin only
/// ("settings:write"), same as commission config.
class PricingPolicy {
  final int rideCancellationGraceSec;
  final double rideCancellationFee;
  final int rideWaitingFreeSec;
  final double rideWaitingPerMinute;
  final double rideWaitingMaxFee;
  final int deliveryCancellationGraceSec;
  final double deliveryCancellationFee;
  final double additionalStopFee;
  final double surgeMinMultiplier;
  final double surgeMaxMultiplier;
  final Map<String, double> packageSizeSurcharge;

  PricingPolicy({
    required this.rideCancellationGraceSec,
    required this.rideCancellationFee,
    required this.rideWaitingFreeSec,
    required this.rideWaitingPerMinute,
    required this.rideWaitingMaxFee,
    required this.deliveryCancellationGraceSec,
    required this.deliveryCancellationFee,
    required this.additionalStopFee,
    required this.surgeMinMultiplier,
    required this.surgeMaxMultiplier,
    required this.packageSizeSurcharge,
  });

  factory PricingPolicy.fromJson(Map<String, dynamic> j) => PricingPolicy(
        rideCancellationGraceSec: (j['rideCancellationGraceSec'] as num?)?.toInt() ?? 0,
        rideCancellationFee: _d(j['rideCancellationFee']),
        rideWaitingFreeSec: (j['rideWaitingFreeSec'] as num?)?.toInt() ?? 0,
        rideWaitingPerMinute: _d(j['rideWaitingPerMinute']),
        rideWaitingMaxFee: _d(j['rideWaitingMaxFee']),
        deliveryCancellationGraceSec: (j['deliveryCancellationGraceSec'] as num?)?.toInt() ?? 0,
        deliveryCancellationFee: _d(j['deliveryCancellationFee']),
        additionalStopFee: _d(j['additionalStopFee']),
        surgeMinMultiplier: _d(j['surgeMinMultiplier'] ?? 1),
        surgeMaxMultiplier: _d(j['surgeMaxMultiplier'] ?? 1),
        packageSizeSurcharge: ((j['packageSizeSurcharge'] as Map?) ?? const {})
            .map((k, v) => MapEntry('$k', _d(v))),
      );
}

class CommissionConfigRow {
  final String service; // RIDE | DELIVERY
  final double rate; // 0-1
  final DateTime? updatedAt;
  final String? updatedBy;
  CommissionConfigRow({
    required this.service,
    required this.rate,
    required this.updatedAt,
    required this.updatedBy,
  });
  factory CommissionConfigRow.fromJson(Map<String, dynamic> j) => CommissionConfigRow(
        service: '${j['service'] ?? ''}',
        rate: _d(j['rate']),
        updatedAt: j['updatedAt'] == null ? null : _dt(j['updatedAt']),
        updatedBy: j['updatedBy']?.toString(),
      );
}

/// A ride tier in the "Choose your ride" flow (RideCategory table). commissionRate
/// is nullable — null means "inherit the RIDE service default" from
/// CommissionConfigRow rather than overriding it per-category.
class RideCategory {
  final String id;
  final String key;
  final String name;
  final String description;
  final String? benefit;
  final double baseFare;
  final double perKm;
  final double perMinute;
  final double minimumFare;
  final double? commissionRate;
  final bool active;
  final int sortOrder;
  final List<String> eligibleVehicleClasses; // empty = no restriction
  RideCategory({
    required this.id,
    required this.key,
    required this.name,
    required this.description,
    required this.benefit,
    required this.baseFare,
    required this.perKm,
    required this.perMinute,
    required this.minimumFare,
    required this.commissionRate,
    required this.active,
    required this.sortOrder,
    required this.eligibleVehicleClasses,
  });
  factory RideCategory.fromJson(Map<String, dynamic> j) => RideCategory(
        id: '${j['id']}',
        key: '${j['key'] ?? ''}',
        name: '${j['name'] ?? ''}',
        description: '${j['description'] ?? ''}',
        benefit: j['benefit']?.toString(),
        baseFare: _d(j['baseFare']),
        perKm: _d(j['perKm']),
        perMinute: _d(j['perMinute']),
        minimumFare: _d(j['minimumFare']),
        commissionRate: j['commissionRate'] == null ? null : _d(j['commissionRate']),
        active: j['active'] != false,
        sortOrder: _i(j['sortOrder']),
        eligibleVehicleClasses:
            ((j['eligibleVehicleClasses'] as List?) ?? const []).map((e) => '$e').toList(),
      );
}

/// One of the four fixed delivery vehicle classes (BIKE/CAR/SUV/VAN) and its
/// rate card. commissionRate is nullable — null means "inherit the DELIVERY
/// service default".
class DeliveryVehicleRate {
  final String id;
  final String vehicleClass; // BIKE | CAR | SUV | VAN
  final String name;
  final double initialFee;
  final double perKm;
  final double? commissionRate;
  final bool active;
  DeliveryVehicleRate({
    required this.id,
    required this.vehicleClass,
    required this.name,
    required this.initialFee,
    required this.perKm,
    required this.commissionRate,
    required this.active,
  });
  factory DeliveryVehicleRate.fromJson(Map<String, dynamic> j) => DeliveryVehicleRate(
        id: '${j['id']}',
        vehicleClass: '${j['vehicleClass'] ?? ''}',
        name: '${j['name'] ?? ''}',
        initialFee: _d(j['initialFee']),
        perKm: _d(j['perKm']),
        commissionRate: j['commissionRate'] == null ? null : _d(j['commissionRate']),
        active: j['active'] != false,
      );
}

/// Marketplace-wide financial rollup for a date range, computed live from the
/// FinancialTransaction ledger (GET /api/admin/financial-dashboard) — never
/// cached or estimated.
class FinancialDashboard {
  final double grossMarketplaceVolume;
  final double ravelgoRevenue;
  final double driverEarnings;
  final double refunds;
  final double cancellationFees;
  final double waitingCharges;
  final double rideRevenue;
  final double deliveryRevenue;
  final double cashCommissionRecorded;
  FinancialDashboard({
    required this.grossMarketplaceVolume,
    required this.ravelgoRevenue,
    required this.driverEarnings,
    required this.refunds,
    required this.cancellationFees,
    required this.waitingCharges,
    required this.rideRevenue,
    required this.deliveryRevenue,
    required this.cashCommissionRecorded,
  });
  factory FinancialDashboard.fromJson(Map<String, dynamic> j) => FinancialDashboard(
        grossMarketplaceVolume: _d(j['grossMarketplaceVolume']),
        ravelgoRevenue: _d(j['ravelgoRevenue']),
        driverEarnings: _d(j['driverEarnings']),
        refunds: _d(j['refunds']),
        cancellationFees: _d(j['cancellationFees']),
        waitingCharges: _d(j['waitingCharges']),
        rideRevenue: _d(j['rideRevenue']),
        deliveryRevenue: _d(j['deliveryRevenue']),
        cashCommissionRecorded: _d(j['cashCommissionRecorded']),
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

// Which ride categories a vehicle is eligible for (RideCategory.
// eligibleVehicleClasses) — null means unclassified (won't match any
// category that restricts itself to specific classes).
const List<String> rideVehicleClasses = ['ECONOMY', 'COMFORT', 'PREMIUM', 'LUXURY'];

class AdminVehicle {
  final String id;
  final String brand;
  final String model;
  final String colour;
  final String plateNumber;
  final String year;
  final bool listedForRental;
  final String ownerName;
  final String ownerEmail;
  final String? vehicleClass;
  AdminVehicle({
    required this.id,
    required this.brand,
    required this.model,
    required this.colour,
    required this.plateNumber,
    required this.year,
    required this.listedForRental,
    required this.ownerName,
    required this.ownerEmail,
    required this.vehicleClass,
  });
  factory AdminVehicle.fromJson(Map<String, dynamic> j) {
    final driver = j['driver'] as Map?;
    final user = driver?['user'] as Map?;
    return AdminVehicle(
      id: '${j['id']}',
      brand: '${j['brand'] ?? ''}',
      model: '${j['model'] ?? ''}',
      colour: '${j['colour'] ?? ''}',
      plateNumber: '${j['plateNumber'] ?? ''}',
      year: '${j['year'] ?? ''}',
      listedForRental: j['listedForRental'] == true,
      ownerName: _name(user),
      ownerEmail: '${user?['email'] ?? ''}',
      vehicleClass: j['vehicleClass'] as String?,
    );
  }
}

class LoyaltyTier {
  final String id;
  final String name;
  final int minCompletedTrips;
  final double discountPercent;
  final String? perks;
  LoyaltyTier({
    required this.id,
    required this.name,
    required this.minCompletedTrips,
    required this.discountPercent,
    required this.perks,
  });
  factory LoyaltyTier.fromJson(Map<String, dynamic> j) => LoyaltyTier(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        minCompletedTrips: _i(j['minCompletedTrips']),
        discountPercent: _d(j['discountPercent']),
        perks: j['perks']?.toString(),
      );
}

class Promotion {
  final String id;
  final String code;
  final String description;
  final double discountPercent;
  final bool active;
  final DateTime? expiresAt;
  final int? maxRedemptions;
  final int redemptionCount;
  Promotion({
    required this.id,
    required this.code,
    required this.description,
    required this.discountPercent,
    required this.active,
    required this.expiresAt,
    required this.maxRedemptions,
    required this.redemptionCount,
  });
  factory Promotion.fromJson(Map<String, dynamic> j) => Promotion(
        id: '${j['id']}',
        code: '${j['code'] ?? ''}',
        description: '${j['description'] ?? ''}',
        discountPercent: _d(j['discountPercent']),
        active: j['active'] != false,
        expiresAt: j['expiresAt'] == null ? null : _dt(j['expiresAt']),
        maxRedemptions: j['maxRedemptions'] == null ? null : _i(j['maxRedemptions']),
        redemptionCount: _i(j['redemptionCount']),
      );
}

class AdminUserAccount {
  final String? id;
  final String name;
  final String email;
  final String adminRole; // SUPER_ADMIN | OPERATIONS_MANAGER | SUPPORT_AGENT | FINANCE_VIEWER
  final bool suspended;
  final String status; // INVITED | ACTIVE | SUSPENDED | UNKNOWN
  final bool mfaEnabled;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;
  AdminUserAccount({
    required this.id,
    required this.name,
    required this.email,
    required this.adminRole,
    required this.suspended,
    required this.status,
    required this.mfaEnabled,
    required this.createdAt,
    required this.lastLoginAt,
  });
  factory AdminUserAccount.fromJson(Map<String, dynamic> j) => AdminUserAccount(
        id: j['id']?.toString(),
        name: '${j['name'] ?? ''}',
        email: '${j['email'] ?? ''}',
        adminRole: '${j['adminRole'] ?? 'SUPER_ADMIN'}',
        suspended: j['suspended'] == true,
        status: '${j['status'] ?? 'UNKNOWN'}',
        mfaEnabled: j['mfaEnabled'] == true,
        createdAt: j['createdAt'] == null ? null : _dt(j['createdAt']),
        lastLoginAt: j['lastLoginAt'] == null ? null : _dt(j['lastLoginAt']),
      );
}

class LiveMapDriver {
  final String driverId;
  final String name;
  final double lat;
  final double lng;
  final DateTime updatedAt;
  final String markerStatus; // AVAILABLE | ON_TRIP | LOGISTICS | OFFLINE | INCIDENT
  final String presence; // LIVE | STALE | OFFLINE — freshness, distinct from markerStatus
  final double rating;
  final String? vehicle;
  final String? activeTripId;
  LiveMapDriver({
    required this.driverId,
    required this.name,
    required this.lat,
    required this.lng,
    required this.updatedAt,
    required this.markerStatus,
    required this.presence,
    required this.rating,
    required this.vehicle,
    required this.activeTripId,
  });
  factory LiveMapDriver.fromJson(Map<String, dynamic> j) => LiveMapDriver(
        driverId: '${j['driverId']}',
        name: '${j['name'] ?? ''}',
        lat: _d(j['lat']),
        lng: _d(j['lng']),
        updatedAt: _dt(j['updatedAt']),
        markerStatus: '${j['markerStatus'] ?? 'OFFLINE'}',
        presence: '${j['presence'] ?? 'OFFLINE'}',
        rating: _d(j['rating']),
        vehicle: j['vehicle']?.toString(),
        activeTripId: j['activeTripId']?.toString(),
      );
}

class LiveMapTrip {
  final String id;
  final String status;
  final String riderName;
  final String? driverName;
  final String pickup;
  final String destination;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;
  final double fare;
  final String? paymentMethod;
  final String? paymentStatus;
  LiveMapTrip({
    required this.id,
    required this.status,
    required this.riderName,
    required this.driverName,
    required this.pickup,
    required this.destination,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.fare,
    required this.paymentMethod,
    required this.paymentStatus,
  });
  factory LiveMapTrip.fromJson(Map<String, dynamic> j) => LiveMapTrip(
        id: '${j['id']}',
        status: '${j['status'] ?? ''}',
        riderName: '${j['riderName'] ?? ''}',
        driverName: j['driverName']?.toString(),
        pickup: '${j['pickup'] ?? ''}',
        destination: '${j['destination'] ?? ''}',
        pickupLat: j['pickupLat'] == null ? null : _d(j['pickupLat']),
        pickupLng: j['pickupLng'] == null ? null : _d(j['pickupLng']),
        dropoffLat: j['dropoffLat'] == null ? null : _d(j['dropoffLat']),
        dropoffLng: j['dropoffLng'] == null ? null : _d(j['dropoffLng']),
        fare: _d(j['fare']),
        paymentMethod: j['paymentMethod']?.toString(),
        paymentStatus: j['paymentStatus']?.toString(),
      );
}

/// One active trip's rider, for the Live Monitoring "Riders" tab. lat/lng/
/// presence are only ever non-null once the rider app has actually reported
/// a real position for this trip (POST /trips/:id/rider-location) — never
/// defaulted or fabricated.
class LiveMapRider {
  final String tripId;
  final String riderName;
  final String status;
  final String pickup;
  final String destination;
  final String? driverName;
  final double? lat;
  final double? lng;
  final DateTime? updatedAt;
  final String? presence; // LIVE | STALE, or null if never reported
  LiveMapRider({
    required this.tripId,
    required this.riderName,
    required this.status,
    required this.pickup,
    required this.destination,
    required this.driverName,
    required this.lat,
    required this.lng,
    required this.updatedAt,
    required this.presence,
  });
  factory LiveMapRider.fromJson(Map<String, dynamic> j) => LiveMapRider(
        tripId: '${j['tripId']}',
        riderName: '${j['riderName'] ?? ''}',
        status: '${j['status'] ?? ''}',
        pickup: '${j['pickup'] ?? ''}',
        destination: '${j['destination'] ?? ''}',
        driverName: j['driverName']?.toString(),
        lat: j['lat'] == null ? null : _d(j['lat']),
        lng: j['lng'] == null ? null : _d(j['lng']),
        updatedAt: j['updatedAt'] == null ? null : _dt(j['updatedAt']),
        presence: j['presence']?.toString(),
      );
}

/// One active delivery, for the Live Monitoring "Packages" tab. The courier's
/// position is the SAME driver GPS feed as the Drivers tab (a package has no
/// location of its own) — lat/lng/presence are null until that driver has
/// reported at least one position.
class LiveMapPackage {
  final String id;
  final String senderName;
  final String recipientName;
  final String? courierName;
  final String pickupAddress;
  final String dropoffAddress;
  final String status;
  final double? lat;
  final double? lng;
  final DateTime? updatedAt;
  final String? presence;
  LiveMapPackage({
    required this.id,
    required this.senderName,
    required this.recipientName,
    required this.courierName,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.status,
    required this.lat,
    required this.lng,
    required this.updatedAt,
    required this.presence,
  });
  factory LiveMapPackage.fromJson(Map<String, dynamic> j) => LiveMapPackage(
        id: '${j['id']}',
        senderName: '${j['senderName'] ?? ''}',
        recipientName: '${j['recipientName'] ?? ''}',
        courierName: j['courierName']?.toString(),
        pickupAddress: '${j['pickupAddress'] ?? ''}',
        dropoffAddress: '${j['dropoffAddress'] ?? ''}',
        status: '${j['status'] ?? ''}',
        lat: j['lat'] == null ? null : _d(j['lat']),
        lng: j['lng'] == null ? null : _d(j['lng']),
        updatedAt: j['updatedAt'] == null ? null : _dt(j['updatedAt']),
        presence: j['presence']?.toString(),
      );
}

/// One currently-active rental booking, for the Live Monitoring "Rentals"
/// tab. locationAvailable is always false today — RavelGo's rental listings
/// are a driver's own vehicle offered for a self-drive reservation, with no
/// GPS/telematics source anywhere in the data model. Real lifecycle data
/// only; never a fabricated coordinate.
class LiveMapRental {
  final String id;
  final String vehicle;
  final String plateNumber;
  final String renterName;
  final String ownerName;
  final DateTime startDate;
  final DateTime endDate;
  final String status;
  final bool locationAvailable;
  LiveMapRental({
    required this.id,
    required this.vehicle,
    required this.plateNumber,
    required this.renterName,
    required this.ownerName,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.locationAvailable,
  });
  factory LiveMapRental.fromJson(Map<String, dynamic> j) => LiveMapRental(
        id: '${j['id']}',
        vehicle: '${j['vehicle'] ?? ''}',
        plateNumber: '${j['plateNumber'] ?? ''}',
        renterName: '${j['renterName'] ?? ''}',
        ownerName: '${j['ownerName'] ?? ''}',
        startDate: _dt(j['startDate']),
        endDate: _dt(j['endDate']),
        status: '${j['status'] ?? ''}',
        locationAvailable: j['locationAvailable'] == true,
      );
}

class LiveMapData {
  final List<LiveMapDriver> drivers;
  final List<LiveMapTrip> trips;
  final List<LiveMapRider> riders;
  final List<LiveMapPackage> packages;
  final List<LiveMapRental> rentals;
  LiveMapData({
    required this.drivers,
    required this.trips,
    required this.riders,
    required this.packages,
    required this.rentals,
  });
  factory LiveMapData.fromJson(Map<String, dynamic> j) => LiveMapData(
        drivers: ((j['drivers'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(LiveMapDriver.fromJson).toList(),
        trips: ((j['trips'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(LiveMapTrip.fromJson).toList(),
        riders: ((j['riders'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(LiveMapRider.fromJson).toList(),
        packages: ((j['packages'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(LiveMapPackage.fromJson).toList(),
        rentals: ((j['rentals'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(LiveMapRental.fromJson).toList(),
      );
}

class PaymentSettings {
  final double cashPaymentLimit;
  final bool cashPaymentEnabled;
  final bool cardPaymentEnabled;
  final bool walletPaymentEnabled;
  PaymentSettings({
    required this.cashPaymentLimit,
    required this.cashPaymentEnabled,
    required this.cardPaymentEnabled,
    required this.walletPaymentEnabled,
  });
  factory PaymentSettings.fromJson(Map<String, dynamic> j) => PaymentSettings(
        cashPaymentLimit: _d(j['cashPaymentLimit']),
        cashPaymentEnabled: j['cashPaymentEnabled'] != false,
        cardPaymentEnabled: j['cardPaymentEnabled'] != false,
        walletPaymentEnabled: j['walletPaymentEnabled'] != false,
      );
}

class CashReconciliationRow {
  final String driverId;
  final String driverName;
  final String driverEmail;
  final double expectedCash;
  final int cashTripCount;
  final double submittedCash;
  final double outstandingCash;
  final String status; // CLEAR | OUTSTANDING | REVIEW_REQUIRED
  CashReconciliationRow({
    required this.driverId,
    required this.driverName,
    required this.driverEmail,
    required this.expectedCash,
    required this.cashTripCount,
    required this.submittedCash,
    required this.outstandingCash,
    required this.status,
  });
  factory CashReconciliationRow.fromJson(Map<String, dynamic> j) => CashReconciliationRow(
        driverId: '${j['driverId']}',
        driverName: '${j['driverName'] ?? ''}',
        driverEmail: '${j['driverEmail'] ?? ''}',
        expectedCash: _d(j['expectedCash']),
        cashTripCount: _i(j['cashTripCount']),
        submittedCash: _d(j['submittedCash']),
        outstandingCash: _d(j['outstandingCash']),
        status: '${j['status'] ?? 'CLEAR'}',
      );
}

class AdminPayment {
  final String id;
  final String tripId;
  final String riderName;
  final double amount;
  final String method; // CARD | CASH | WALLET
  final String status; // PENDING | SUCCEEDED | FAILED | REFUNDED
  final DateTime createdAt;
  final DateTime? paidAt;
  AdminPayment({
    required this.id,
    required this.tripId,
    required this.riderName,
    required this.amount,
    required this.method,
    required this.status,
    required this.createdAt,
    required this.paidAt,
  });
  factory AdminPayment.fromJson(Map<String, dynamic> j) => AdminPayment(
        id: '${j['id']}',
        tripId: '${j['tripId']}',
        riderName: _name(j['user'] as Map?),
        amount: _d(j['amount']),
        method: '${j['method'] ?? 'CARD'}',
        status: '${j['status'] ?? ''}',
        createdAt: _dt(j['createdAt']),
        paidAt: j['paidAt'] == null ? null : _dt(j['paidAt']),
      );
}

class AdminApi {
  static List _list(dynamic data) => (data is Map ? data['data'] : data) as List? ?? const [];

  static Future<DashboardStats> dashboard() async =>
      DashboardStats.fromJson(await ApiClient.get('/api/admin/dashboard') as Map<String, dynamic>);

  /// Drivers, optionally narrowed server-side to one approval status
  /// (GET /api/drivers?status=PENDING_REVIEW). Filtering on the server means
  /// the pending queue is the whole queue, not just whichever pending drivers
  /// happened to fall inside the first page of "all drivers".
  static Future<List<AdminDriver>> drivers({String? status}) async {
    final query = status == null ? '' : '&status=${Uri.encodeQueryComponent(status)}';
    final data = await ApiClient.get('/api/drivers?pageSize=100$query');
    return _list(data).whereType<Map<String, dynamic>>().map(AdminDriver.fromJson).toList();
  }

  static Future<AdminDriver> driver(String id) async =>
      AdminDriver.fromJson(await ApiClient.get('/api/drivers/$id') as Map<String, dynamic>);

  static Future<void> setDriverStatus(String id, String status) async {
    await ApiClient.patch('/api/drivers/$id/status', {'status': status});
  }

  static Future<void> reviewDocument(String id, String status, {String? rejectionReason}) async {
    await ApiClient.patch('/api/documents/$id/review', {
      'status': status,
      if (rejectionReason != null && rejectionReason.isNotEmpty) 'rejectionReason': rejectionReason,
    });
  }

  /// A short-lived signed URL to view one of a driver's uploaded onboarding
  /// documents. Fetched fresh each time — never cached or persisted client-side.
  static Future<String> documentSignedUrl(String driverId, String documentId) async {
    final data = await ApiClient.get('/api/drivers/$driverId/documents/$documentId/url') as Map<String, dynamic>;
    return '${data['url']}';
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

  static Future<AdminTrip> trip(String id) async =>
      AdminTrip.fromJson(await ApiClient.get('/api/trips/$id') as Map<String, dynamic>);

  static Future<List<AnalyticsDay>> analytics() async {
    final data = await ApiClient.get('/api/admin/analytics') as Map<String, dynamic>;
    final days = (data['days'] as List?) ?? const [];
    return days.whereType<Map<String, dynamic>>().map(AnalyticsDay.fromJson).toList();
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

  // ---- Loyalty tiers & promotions ----
  static Future<List<LoyaltyTier>> loyaltyTiers() async {
    final data = await ApiClient.get('/api/loyalty-tiers');
    return (data as List).whereType<Map<String, dynamic>>().map(LoyaltyTier.fromJson).toList();
  }

  static Future<LoyaltyTier> createLoyaltyTier({
    required String name,
    required int minCompletedTrips,
    required double discountPercent,
    String? perks,
  }) async {
    final data = await ApiClient.post('/api/loyalty-tiers', {
      'name': name,
      'minCompletedTrips': minCompletedTrips,
      'discountPercent': discountPercent,
      if (perks != null && perks.isNotEmpty) 'perks': perks,
    });
    return LoyaltyTier.fromJson(data as Map<String, dynamic>);
  }

  static Future<List<Promotion>> promotions() async {
    final data = await ApiClient.get('/api/promotions');
    return (data as List).whereType<Map<String, dynamic>>().map(Promotion.fromJson).toList();
  }

  static Future<Promotion> createPromotion({
    required String code,
    required String description,
    required double discountPercent,
    DateTime? expiresAt,
    int? maxRedemptions,
  }) async {
    final data = await ApiClient.post('/api/promotions', {
      'code': code,
      'description': description,
      'discountPercent': discountPercent,
      if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
      if (maxRedemptions != null) 'maxRedemptions': maxRedemptions,
    });
    return Promotion.fromJson(data as Map<String, dynamic>);
  }

  // ---- Admin user management (Super Admin only; backend enforces this) ----
  static Future<List<AdminUserAccount>> adminUsers() async {
    final data = await ApiClient.get('/api/admin-users');
    return (data as List).whereType<Map<String, dynamic>>().map(AdminUserAccount.fromJson).toList();
  }

  /// The calling admin's own profile — any Admin-group member, not just
  /// Super Admin. Used by AdminProfileScreen and the post-login MFA gate.
  static Future<AdminUserAccount> me() async {
    final data = await ApiClient.get('/api/admin-users/me');
    return AdminUserAccount.fromJson(data as Map<String, dynamic>);
  }

  static Future<AdminUserAccount> adminUser(String id) async {
    final data = await ApiClient.get('/api/admin-users/$id');
    return AdminUserAccount.fromJson(data as Map<String, dynamic>);
  }

  static Future<AdminUserAccount> createAdminUser({
    required String email,
    required String firstName,
    required String lastName,
    required String adminRole,
  }) async {
    final data = await ApiClient.post('/api/admin-users', {
      'email': email,
      'firstName': firstName,
      'lastName': lastName,
      'adminRole': adminRole,
    });
    return AdminUserAccount.fromJson(data as Map<String, dynamic>);
  }

  static Future<AdminUserAccount> setAdminUserRole(String id, String adminRole) async {
    final data = await ApiClient.patch('/api/admin-users/$id/role', {'adminRole': adminRole});
    return AdminUserAccount.fromJson(data as Map<String, dynamic>);
  }

  static Future<AdminUserAccount> setAdminUserSuspended(String id, bool suspended) async {
    final data = await ApiClient.patch('/api/admin-users/$id/status', {'suspended': suspended});
    return AdminUserAccount.fromJson(data as Map<String, dynamic>);
  }

  static Future<AdminUserAccount> resendAdminInvitation(String id) async {
    final data = await ApiClient.post('/api/admin-users/$id/resend-invitation', {});
    return AdminUserAccount.fromJson(data as Map<String, dynamic>);
  }

  static Future<AdminUserAccount> requestAdminPasswordReset(String id) async {
    final data = await ApiClient.post('/api/admin-users/$id/password-reset', {});
    return AdminUserAccount.fromJson(data as Map<String, dynamic>);
  }

  /// Audit-trail marker called right after the calling admin finishes TOTP
  /// enrollment directly against Cognito (see AuthService.completeMfaEnrollment).
  static Future<void> recordMfaEnrolled() async {
    await ApiClient.post('/api/admin-users/me/mfa-enrolled', {});
  }

  // ---- Vehicle inventory (admin, cross-driver) ----
  static Future<List<AdminVehicle>> vehicles() async {
    final data = await ApiClient.get('/api/vehicles?pageSize=100');
    return _list(data).whereType<Map<String, dynamic>>().map(AdminVehicle.fromJson).toList();
  }

  /// Admin-set (or clear, with null) a vehicle's ride-category eligibility
  /// class — PATCH /api/admin/vehicles/:id/class. Independent of whatever the
  /// driver self-declared when adding the vehicle; this is what
  /// services/matching.ts actually reads when a RideCategory restricts
  /// itself to specific vehicle classes.
  static Future<void> setVehicleClass(String vehicleId, String? vehicleClass) async {
    await ApiClient.patch('/api/admin/vehicles/$vehicleId/class', {'vehicleClass': vehicleClass});
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

  // transactionId is required: the backend refuses to mark a payout COMPLETED
  // without a real transfer reference (SE-4) — see payouts_screen.dart's
  // _complete() for why this can't be left blank.
  static Future<AdminPayout> completePayout(String id, {required String transactionId}) async {
    final data = await ApiClient.post('/api/payouts/$id/complete', {'transactionId': transactionId});
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

  /// Super Admin / Operations Manager only — the backend enforces this.
  static Future<SubscriptionPlan> createSubscriptionPlan({
    required String name,
    required String description,
    required double priceMonthly,
  }) async {
    final data = await ApiClient.post('/api/subscription-plans', {
      'name': name,
      'description': description,
      'priceMonthly': priceMonthly,
    });
    return SubscriptionPlan.fromJson(data as Map<String, dynamic>);
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

  // ---- Commission config (Super Admin write; every Admin preset can read —
  // see requireAdminPermission("settings:write") in pricing.routes.ts) ----
  static Future<List<CommissionConfigRow>> commissionConfig() async {
    final data = await ApiClient.get('/api/admin/commission-config');
    return (data as List).whereType<Map<String, dynamic>>().map(CommissionConfigRow.fromJson).toList();
  }

  static Future<CommissionConfigRow> updateCommissionRate(String service, double rate) async {
    final data = await ApiClient.patch('/api/admin/commission-config/$service', {'rate': rate});
    return CommissionConfigRow.fromJson(data as Map<String, dynamic>);
  }

  // ---- Pricing policy (Super Admin write; every Admin preset can read) ----
  static Future<PricingPolicy> pricingPolicy() async {
    final data = await ApiClient.get('/api/admin/pricing-policy');
    return PricingPolicy.fromJson(data as Map<String, dynamic>);
  }

  /// Pass only the fields being changed; omit the rest.
  static Future<PricingPolicy> updatePricingPolicy({
    int? rideCancellationGraceSec,
    double? rideCancellationFee,
    int? rideWaitingFreeSec,
    double? rideWaitingPerMinute,
    double? rideWaitingMaxFee,
    int? deliveryCancellationGraceSec,
    double? deliveryCancellationFee,
    double? additionalStopFee,
    double? surgeMinMultiplier,
    double? surgeMaxMultiplier,
    Map<String, double>? packageSizeSurcharge,
  }) async {
    final data = await ApiClient.patch('/api/admin/pricing-policy', {
      if (rideCancellationGraceSec != null) 'rideCancellationGraceSec': rideCancellationGraceSec,
      if (rideCancellationFee != null) 'rideCancellationFee': rideCancellationFee,
      if (rideWaitingFreeSec != null) 'rideWaitingFreeSec': rideWaitingFreeSec,
      if (rideWaitingPerMinute != null) 'rideWaitingPerMinute': rideWaitingPerMinute,
      if (rideWaitingMaxFee != null) 'rideWaitingMaxFee': rideWaitingMaxFee,
      if (deliveryCancellationGraceSec != null) 'deliveryCancellationGraceSec': deliveryCancellationGraceSec,
      if (deliveryCancellationFee != null) 'deliveryCancellationFee': deliveryCancellationFee,
      if (additionalStopFee != null) 'additionalStopFee': additionalStopFee,
      if (surgeMinMultiplier != null) 'surgeMinMultiplier': surgeMinMultiplier,
      if (surgeMaxMultiplier != null) 'surgeMaxMultiplier': surgeMaxMultiplier,
      if (packageSizeSurcharge != null) 'packageSizeSurcharge': packageSizeSurcharge,
    });
    return PricingPolicy.fromJson(data as Map<String, dynamic>);
  }

  // ---- Ride categories (pricing:write to write; reads open to any Admin) ----
  static Future<List<RideCategory>> rideCategories() async {
    final data = await ApiClient.get('/api/admin/ride-categories');
    return (data as List).whereType<Map<String, dynamic>>().map(RideCategory.fromJson).toList();
  }

  static Future<RideCategory> createRideCategory({
    required String key,
    required String name,
    required String description,
    String? benefit,
    required double baseFare,
    required double perKm,
    required double perMinute,
    double minimumFare = 0,
    double? commissionRate,
    int sortOrder = 0,
    List<String> eligibleVehicleClasses = const [],
    bool active = true,
  }) async {
    final data = await ApiClient.post('/api/admin/ride-categories', {
      'key': key,
      'name': name,
      'description': description,
      if (benefit != null && benefit.isNotEmpty) 'benefit': benefit,
      'baseFare': baseFare,
      'perKm': perKm,
      'perMinute': perMinute,
      'minimumFare': minimumFare,
      if (commissionRate != null) 'commissionRate': commissionRate,
      'sortOrder': sortOrder,
      'eligibleVehicleClasses': eligibleVehicleClasses,
      'active': active,
    });
    return RideCategory.fromJson(data as Map<String, dynamic>);
  }

  static Future<RideCategory> updateRideCategory(
    String id, {
    String? name,
    String? description,
    String? benefit,
    double? baseFare,
    double? perKm,
    double? perMinute,
    double? minimumFare,
    double? commissionRate,
    // Explicit flag because "clear the override, inherit the service default"
    // means sending commissionRate: null, indistinguishable from "unset" if we
    // only checked commissionRate != null.
    bool clearCommissionRate = false,
    int? sortOrder,
    List<String>? eligibleVehicleClasses,
    bool? active,
  }) async {
    final data = await ApiClient.patch('/api/admin/ride-categories/$id', {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (benefit != null) 'benefit': benefit,
      if (baseFare != null) 'baseFare': baseFare,
      if (perKm != null) 'perKm': perKm,
      if (perMinute != null) 'perMinute': perMinute,
      if (minimumFare != null) 'minimumFare': minimumFare,
      if (clearCommissionRate)
        'commissionRate': null
      else if (commissionRate != null)
        'commissionRate': commissionRate,
      if (sortOrder != null) 'sortOrder': sortOrder,
      if (eligibleVehicleClasses != null) 'eligibleVehicleClasses': eligibleVehicleClasses,
      if (active != null) 'active': active,
    });
    return RideCategory.fromJson(data as Map<String, dynamic>);
  }

  // ---- Delivery vehicle rates (fixed 4 rows, PATCH-only) ----
  static Future<List<DeliveryVehicleRate>> deliveryVehicleRates() async {
    final data = await ApiClient.get('/api/admin/delivery-vehicle-rates');
    return (data as List).whereType<Map<String, dynamic>>().map(DeliveryVehicleRate.fromJson).toList();
  }

  static Future<DeliveryVehicleRate> updateDeliveryVehicleRate(
    String vehicleClass, {
    String? name,
    double? initialFee,
    double? perKm,
    double? commissionRate,
    bool clearCommissionRate = false,
    bool? active,
  }) async {
    final data = await ApiClient.patch('/api/admin/delivery-vehicle-rates/$vehicleClass', {
      if (name != null) 'name': name,
      if (initialFee != null) 'initialFee': initialFee,
      if (perKm != null) 'perKm': perKm,
      if (clearCommissionRate)
        'commissionRate': null
      else if (commissionRate != null)
        'commissionRate': commissionRate,
      if (active != null) 'active': active,
    });
    return DeliveryVehicleRate.fromJson(data as Map<String, dynamic>);
  }

  // ---- Financial dashboard (read-only, any Admin) ----
  static Future<FinancialDashboard> financialDashboard({DateTime? from, DateTime? to}) async {
    final params = <String>[];
    if (from != null) params.add('from=${Uri.encodeComponent(from.toUtc().toIso8601String())}');
    if (to != null) params.add('to=${Uri.encodeComponent(to.toUtc().toIso8601String())}');
    final qs = params.isEmpty ? '' : '?${params.join('&')}';
    final data = await ApiClient.get('/api/admin/financial-dashboard$qs');
    return FinancialDashboard.fromJson(data as Map<String, dynamic>);
  }

  // ---- Live map (real driver locations + active trips) ----
  static Future<LiveMapData> liveMap() async {
    final data = await ApiClient.get('/api/admin/live-map');
    return LiveMapData.fromJson(data as Map<String, dynamic>);
  }

  // ---- Payment settings (the ₦15,000 cash cap and method toggles) ----
  static Future<PaymentSettings> paymentSettings() async {
    final data = await ApiClient.get('/api/settings/payment');
    return PaymentSettings.fromJson(data as Map<String, dynamic>);
  }

  /// Super Admin only — the backend enforces this regardless of what this
  /// screen shows. Every change is audited server-side.
  static Future<PaymentSettings> updatePaymentSettings({
    double? cashPaymentLimit,
    bool? cashPaymentEnabled,
    bool? cardPaymentEnabled,
    bool? walletPaymentEnabled,
  }) async {
    final data = await ApiClient.patch('/api/admin/settings/payment', {
      if (cashPaymentLimit != null) 'cashPaymentLimit': cashPaymentLimit,
      if (cashPaymentEnabled != null) 'cashPaymentEnabled': cashPaymentEnabled,
      if (cardPaymentEnabled != null) 'cardPaymentEnabled': cardPaymentEnabled,
      if (walletPaymentEnabled != null) 'walletPaymentEnabled': walletPaymentEnabled,
    });
    return PaymentSettings.fromJson(data as Map<String, dynamic>);
  }

  // ---- Cash reconciliation ----
  static Future<List<CashReconciliationRow>> cashReconciliation() async {
    final data = await ApiClient.get('/api/admin/cash-reconciliation');
    return (data as List).whereType<Map<String, dynamic>>().map(CashReconciliationRow.fromJson).toList();
  }

  /// Record that a driver has physically handed in cash. Finance/Super Admin
  /// only; always audited server-side.
  static Future<void> recordCashRemittance({
    required String driverId,
    required double amount,
    String? note,
  }) async {
    await ApiClient.post('/api/admin/cash-remittances', {
      'driverId': driverId,
      'amount': amount,
      if (note != null && note.isNotEmpty) 'note': note,
    });
  }

  // ---- All payments (for the Payments & Cash overview) ----
  static Future<List<AdminPayment>> payments() async {
    final data = await ApiClient.get('/api/payments?pageSize=100');
    return _list(data).whereType<Map<String, dynamic>>().map(AdminPayment.fromJson).toList();
  }

  // ---- Notifications (AA-2) ----
  // GET/PATCH/POST /api/notifications* are role-agnostic — every row is
  // already scoped to the authenticated caller server-side, so an Admin
  // caller here sees exactly the rows notifyAllAdmins() (backend
  // lib/notifications.ts) wrote for them, no separate admin endpoint needed.
  static Future<AdminNotificationPage> notifications({int page = 1, int pageSize = 30}) async {
    final data = await ApiClient.get('/api/notifications?page=$page&pageSize=$pageSize') as Map<String, dynamic>;
    final list = (data['data'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AdminNotification.fromJson)
        .toList();
    return AdminNotificationPage(
      items: list,
      unreadCount: (data['unreadCount'] as num?)?.toInt() ?? 0,
      total: (data['total'] as num?)?.toInt() ?? list.length,
    );
  }

  static Future<void> markNotificationRead(String id) async {
    await ApiClient.patch('/api/notifications/$id/read');
  }

  static Future<void> markAllNotificationsRead() async {
    await ApiClient.post('/api/notifications/read-all');
  }
}

/// A real, backend-persisted notification (see backend `Notification` model
/// and `notifications.routes.ts`), same shape the Customer App's
/// NotificationsApi consumes — never fabricated client-side.
class AdminNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final bool read;
  final String? referenceType; // e.g. "TRIP", "COURIER_REQUEST", "RENTAL_BOOKING", "EMERGENCY_ALERT"
  final String? referenceId;
  final DateTime createdAt;

  AdminNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.referenceType,
    this.referenceId,
  });

  factory AdminNotification.fromJson(Map<String, dynamic> j) => AdminNotification(
        id: '${j['id']}',
        type: '${j['type'] ?? ''}',
        title: '${j['title'] ?? ''}',
        body: '${j['body'] ?? ''}',
        read: j['read'] == true,
        referenceType: j['referenceType']?.toString(),
        referenceId: j['referenceId']?.toString(),
        createdAt: _dt(j['createdAt']),
      );
}

class AdminNotificationPage {
  final List<AdminNotification> items;
  final int unreadCount;
  final int total;
  AdminNotificationPage({required this.items, required this.unreadCount, required this.total});
}
