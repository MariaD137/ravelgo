import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ravelgo_admin/services/auth_service.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, dynamic>? body;

  ApiException(this.statusCode, this.message, {this.body});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  static final ApiClient _instance = ApiClient._();
  factory ApiClient() => _instance;
  ApiClient._();

  final HttpClient _http = HttpClient();
  String get _baseUrl {
    final url = dotenv.env['API_BASE_URL'];
    if (url == null || url.isEmpty) {
      throw StateError('API_BASE_URL is not set in .env');
    }
    return url;
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService().getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<dynamic> get(String path, {Map<String, String>? queryParams}) async {
    final uri = Uri.parse('$_baseUrl/api$path').replace(queryParameters: queryParams);
    final request = await _http.getUrl(uri);
    final headers = await _authHeaders();
    headers.forEach((k, v) => request.headers.set(k, v));
    final response = await request.close();
    return _handleResponse(response);
  }

  Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$_baseUrl/api$path');
    final request = await _http.postUrl(uri);
    final headers = await _authHeaders();
    headers.forEach((k, v) => request.headers.set(k, v));
    if (body != null) {
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    return _handleResponse(response);
  }

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$_baseUrl/api$path');
    final request = await _http.patchUrl(uri);
    final headers = await _authHeaders();
    headers.forEach((k, v) => request.headers.set(k, v));
    if (body != null) {
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    return _handleResponse(response);
  }

  Future<dynamic> delete(String path) async {
    final uri = Uri.parse('$_baseUrl/api$path');
    final request = await _http.deleteUrl(uri);
    final headers = await _authHeaders();
    headers.forEach((k, v) => request.headers.set(k, v));
    final response = await request.close();
    return _handleResponse(response);
  }

  Future<dynamic> _handleResponse(HttpClientResponse response) async {
    final body = await response.transform(utf8.decoder).join();
    final statusCode = response.statusCode;

    if (body.isEmpty) {
      if (statusCode >= 200 && statusCode < 300) return null;
      throw ApiException(statusCode, 'Request failed');
    }

    final decoded = jsonDecode(body);

    if (statusCode == 401) {
      final refreshed = await AuthService().refreshSession();
      if (!refreshed) {
        throw ApiException(401, 'Session expired');
      }
      throw ApiException(401, 'Retry after refresh');
    }

    if (statusCode >= 200 && statusCode < 300) return decoded;

    final message = decoded is Map ? (decoded['error']?['message'] ?? decoded['error'] ?? 'Request failed') : 'Request failed';
    throw ApiException(statusCode, message.toString(), body: decoded is Map<String, dynamic> ? decoded : null);
  }
}
