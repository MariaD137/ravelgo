import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_client.dart';

/// A driver's own uploaded documents (license, vehicle papers, background
/// check, ...) — GET /api/documents/me, POST /api/uploads/presign, and
/// POST /api/documents on the backend. The upload itself is a two-step
/// hand-off, not a single call: [uploadAndRegister] gets a short-lived S3
/// presigned URL, PUTs the file bytes straight to S3 (bypassing this app's
/// own backend entirely for the bytes themselves), then registers the
/// resulting object key as a DriverDocument row. Until real S3 buckets are
/// provisioned, the presign step itself returns a clean, real error rather
/// than a fabricated success — this class never fakes that outcome.
class DocumentApi {
  DocumentApi(this._client, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final ApiClient _client;
  final http.Client _http;

  Future<List<Map<String, dynamic>>> listMine() async {
    final res = await _client.get('/api/documents/me') as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// Uploads [bytes] to S3 via a presigned URL, then registers it as a
  /// document titled [title]. Throws [ApiException] on any real failure
  /// (including a "bucket not configured" 500 from /uploads/presign, or a
  /// direct S3 PUT failure) — there is no fallback path that pretends this
  /// succeeded.
  Future<Map<String, dynamic>> uploadAndRegister({
    required String title,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final presign =
        await _client.post(
              '/api/uploads/presign',
              body: {'bucket': 'documents', 'fileName': fileName, 'contentType': contentType},
            )
            as Map<String, dynamic>;
    final uploadUrl = presign['uploadUrl'] as String;
    final fileKey = presign['fileKey'] as String;

    // Direct S3 PUT — outside ApiClient, since this goes to the presigned
    // S3 host, not this app's own backend, and needs no Authorization
    // header (the presigned URL itself is the credential).
    final putRes = await _http.put(Uri.parse(uploadUrl), headers: {'Content-Type': contentType}, body: bytes);
    if (putRes.statusCode < 200 || putRes.statusCode >= 300) {
      throw ApiException(
        statusCode: putRes.statusCode,
        code: 'UPLOAD_FAILED',
        message: 'Could not upload the file to storage (status ${putRes.statusCode}).',
      );
    }

    return await _client.post('/api/documents', body: {'title': title, 'fileKey': fileKey}) as Map<String, dynamic>;
  }
}
