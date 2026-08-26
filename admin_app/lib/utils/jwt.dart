import 'dart:convert';

/// Decodes a JWT's payload (the middle base64url segment) into a Map,
/// without verifying the signature — this is only ever used client-side to
/// decide what the UI shows before the first API call; the backend
/// independently verifies the signature and re-checks every claim it
/// relies on. Returns null for anything that isn't a well-formed
/// three-segment JWT.
Map<String, dynamic>? decodeJwtPayload(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final decoded = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    if (decoded is! Map<String, dynamic>) return null;
    return decoded;
  } catch (_) {
    return null;
  }
}
