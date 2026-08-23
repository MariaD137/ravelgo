/// A trip from the driver's own history — parsed from GET /api/trips/mine's
/// `data` entries (real Trip rows, including the nested `rider` relation for
/// display). Status is kept as the backend's own raw string
/// (REQUESTED/MATCHED/IN_PROGRESS/COMPLETED/CANCELLED/DISPUTED) rather than
/// a Flutter-only enum, so this model can never drift out of sync with a
/// status value the backend actually uses.
class Trip {
  final String id;
  final String pickup;
  final String destination;
  final String status;
  final double estimatedFare;
  final double? finalFare;
  final DateTime requestedAt;
  final String riderName;

  const Trip({
    required this.id,
    required this.pickup,
    required this.destination,
    required this.status,
    required this.estimatedFare,
    this.finalFare,
    required this.requestedAt,
    required this.riderName,
  });

  factory Trip.fromJson(Map<String, dynamic> json) {
    final rider = json['rider'] as Map<String, dynamic>?;
    final riderName = rider == null ? '' : '${rider['firstName'] ?? ''} ${rider['lastName'] ?? ''}'.trim();
    return Trip(
      id: json['id'] as String,
      pickup: json['pickup'] as String? ?? '',
      destination: json['destination'] as String? ?? '',
      status: json['status'] as String? ?? 'REQUESTED',
      estimatedFare: (json['estimatedFare'] as num?)?.toDouble() ?? 0,
      finalFare: (json['finalFare'] as num?)?.toDouble(),
      requestedAt: DateTime.tryParse(json['requestedAt'] as String? ?? '') ?? DateTime.now(),
      riderName: riderName.isEmpty ? 'Rider' : riderName,
    );
  }

  bool get isCancelled => status == 'CANCELLED';
  double get fare => finalFare ?? estimatedFare;
}
