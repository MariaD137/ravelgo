import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_admin/utils/jwt.dart';

// decodeJwtPayload only decodes the middle segment — it never checks the
// signature (that's the backend's job, via a real Cognito JWKS verify) —
// so these tokens are hand-built with garbage headers/signatures on
// purpose, to prove decoding doesn't depend on them being real.
String _fakeJwt(Map<String, dynamic> payload) {
  String segment(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${segment({
        'alg': 'RS256'
      })}.${segment(payload)}.fake-signature';
}

void main() {
  test('decodeJwtPayload reads back exactly what was encoded', () {
    final token = _fakeJwt({'cognito:groups': ['Admin'], 'exp': 9999999999});
    final decoded = decodeJwtPayload(token);

    expect(decoded, isNotNull);
    expect(decoded!['cognito:groups'], ['Admin']);
    expect(decoded['exp'], 9999999999);
  });

  test('decodeJwtPayload returns null for a token with the wrong number of segments', () {
    expect(decodeJwtPayload('not-a-jwt'), isNull);
    expect(decodeJwtPayload('only.two'), isNull);
  });

  test('decodeJwtPayload returns null for a payload segment that is not valid base64/JSON', () {
    expect(decodeJwtPayload('header.###not-base64###.sig'), isNull);
  });

  test('decodeJwtPayload handles a token with no cognito:groups claim at all', () {
    final token = _fakeJwt({'sub': 'some-user-id', 'exp': 9999999999});
    final decoded = decodeJwtPayload(token);

    expect(decoded, isNotNull);
    expect(decoded!.containsKey('cognito:groups'), isFalse);
  });
}
