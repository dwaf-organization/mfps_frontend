import 'package:mfps/url_config.dart';
import 'http_helper.dart';

class HospitalStructureApi {
  static String get _baseUrl => UrlConfig.serverUrl;

  // 병동 조회
  // /api/hospital/structure/part?hospital_code=1
  static Future<List<Map<String, dynamic>>> fetchWards({
    required int hospitalCode,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/api/hospital/structure/part?hospital_code=$hospitalCode',
    );
    final decoded = await HttpHelper.getJson(uri);

    if (decoded['code'] != 1) {
      throw Exception((decoded['message'] ?? '병동 조회 실패').toString());
    }

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) return [];

    final parts = data['parts'];
    if (parts is! List) return [];

    return parts.cast<Map<String, dynamic>>();
  }

  // 층 조회
  // /api/hospital/structure/floor?hospital_st_code=1
  static Future<List<Map<String, dynamic>>> fetchFloors({
    required int hospitalStCode,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/api/hospital/structure/floor?hospital_st_code=$hospitalStCode',
    );
    final decoded = await HttpHelper.getJson(uri);

    if (decoded['code'] != 1) {
      throw Exception((decoded['message'] ?? '층 조회 실패').toString());
    }

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) return [];

    final floors = data['floors'];
    if (floors is! List) return [];

    return floors.cast<Map<String, dynamic>>();
  }
}
