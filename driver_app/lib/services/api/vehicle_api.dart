import 'api_client.dart';

/// A driver's own vehicles — GET/POST /api/vehicles/me|vehicles and
/// PATCH /api/vehicles/:id on the backend.
class VehicleApi {
  VehicleApi(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> listMine() async {
    final res = await _client.get('/api/vehicles/me') as List;
    return res.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> create({
    required String brand,
    required String model,
    required String colour,
    required String plateNumber,
    required String year,
    bool isPrimary = false,
  }) async {
    return await _client.post(
          '/api/vehicles',
          body: {
            'brand': brand,
            'model': model,
            'colour': colour,
            'plateNumber': plateNumber,
            'year': year,
            'isPrimary': isPrimary,
          },
        )
        as Map<String, dynamic>;
  }
}
