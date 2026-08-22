import 'api_client.dart';

/// Courier's own API surface — never imports ride_api.dart or
/// rental_api.dart. A 409 [ApiException] from [accept] with
/// `code == 'DRIVER_BUSY'` means the driver already holds an active
/// Ride/Courier/Rental assignment; the backend
/// (services/driver-availability.ts) is the authority on that, this class
/// only surfaces what it says.
class CourierApi {
  CourierApi(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> listAvailable({int page = 1, int pageSize = 20}) async {
    final res =
        await _client.get('/api/courier-requests/available', query: {'page': page, 'pageSize': pageSize})
            as Map<String, dynamic>;
    return (res['data'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getById(String id) async {
    return await _client.get('/api/courier-requests/$id') as Map<String, dynamic>;
  }

  /// Throws [ApiException] with `code == 'DRIVER_BUSY'` (409) if the driver
  /// already has an active assignment, or a plain 409 if another driver won
  /// the request first.
  Future<Map<String, dynamic>> accept(String id) async {
    return await _client.patch('/api/courier-requests/$id/accept') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateStatus(String id, String status, {double? finalFare}) async {
    return await _client.patch(
          '/api/courier-requests/$id/status',
          body: {
            'status': status,
            if (finalFare != null) 'finalFare': finalFare,
          },
        )
        as Map<String, dynamic>;
  }
}
