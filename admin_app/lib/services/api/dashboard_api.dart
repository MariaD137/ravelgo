import 'api_client.dart';

/// Admin dashboard KPIs — GET /api/admin/dashboard on the backend. Returns
/// activeTrips, onlineDrivers, and pendingApprovals (driver documents plus
/// CarPaddy requests awaiting review), computed live from the database —
/// never invented or cached client-side.
class DashboardApi {
  DashboardApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> getKpis() async {
    return await _client.get('/api/admin/dashboard') as Map<String, dynamic>;
  }
}
