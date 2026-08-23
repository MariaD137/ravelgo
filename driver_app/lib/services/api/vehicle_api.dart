import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_client.dart';

/// A driver's own vehicles — GET/POST /api/vehicles/me|vehicles and
/// PATCH /api/vehicles/:id on the backend.
class VehicleApi {
  VehicleApi(this._client, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final ApiClient _client;
  final http.Client _http;

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
    String? imageKey,
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
            if (imageKey != null) 'imageKey': imageKey,
          },
        )
        as Map<String, dynamic>;
  }

  /// Uploads [bytes] to S3 via a presigned URL (same two-step hand-off as
  /// DocumentApi.uploadAndRegister — the bytes go straight to S3, bypassing
  /// this app's own backend), then attaches the resulting object key to
  /// [vehicleId] via PATCH /api/vehicles/:id. Throws [ApiException] on any
  /// real failure (including a "bucket not configured" 500 from
  /// /uploads/presign, or a direct S3 PUT failure) — there is no fallback
  /// path that pretends this succeeded.
  Future<Map<String, dynamic>> uploadImageAndAttach({
    required String vehicleId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final presign =
        await _client.post(
              '/api/uploads/presign',
              body: {'bucket': 'assets', 'fileName': fileName, 'contentType': contentType},
            )
            as Map<String, dynamic>;
    final uploadUrl = presign['uploadUrl'] as String;
    final fileKey = presign['fileKey'] as String;

    final putRes = await _http.put(Uri.parse(uploadUrl), headers: {'Content-Type': contentType}, body: bytes);
    if (putRes.statusCode < 200 || putRes.statusCode >= 300) {
      throw ApiException(
        statusCode: putRes.statusCode,
        code: 'UPLOAD_FAILED',
        message: 'Could not upload the photo to storage (status ${putRes.statusCode}).',
      );
    }

    return await _client.patch('/api/vehicles/$vehicleId', body: {'imageKey': fileKey}) as Map<String, dynamic>;
  }
}
