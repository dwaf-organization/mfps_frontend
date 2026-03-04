import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:mfps/url_config.dart'; // 경로 맞춰서 수정하세요.

class AuthApi {
  AuthApi();

  /// ✅ baseUrl은 url_config.dart의 serverUrl을 그대로 사용
  String get _baseUrl => UrlConfig.serverUrl;

  /// 명세: POST /api/auth/login
  Future<Map<String, dynamic>> login({
    required String hospitalId,
    required String hospitalPassword,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/auth/login');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'hospital_id': hospitalId,
        'hospital_password': hospitalPassword,
      }),
    );

    debugPrint('[LOGIN] status=${response.statusCode}');
    debugPrint('[LOGIN] body=${response.body}');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('로그인 실패(HTTP ${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('서버 응답 형식이 올바르지 않습니다.');
    }

    return Map<String, dynamic>.from(decoded);
  }
}
