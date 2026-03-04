import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'package:mfps/url_config.dart';
import 'package:mfps/storage_keys.dart';

class PatientEditDialog extends StatefulWidget {
  final int patientCode;
  final int fromBedCode;
  final Future<void> Function()? onRefresh;

  const PatientEditDialog({
    super.key,
    required this.patientCode,
    required this.fromBedCode,
    this.onRefresh,
  });

  @override
  State<PatientEditDialog> createState() => _PatientEditDialogState();
}

class _PatientEditDialogState extends State<PatientEditDialog> {
  static const _storage = FlutterSecureStorage();

  // ✅ 환자추가와 동일 톤
  static const _cBorder = Color(0xFFE5E7EB);
  static const _cText = Color(0xFF111827);
  static const _cSubText = Color(0xFF6B7280);
  static const _cGreen = Color(0xFF22C55E);
  static const _cRed = Color(0xFFEF4444);

  // ✅ 드롭박스/달력 보조 톤
  static const _cGreenSoft = Color(0xFFECFDF5);

  late final String _baseUrl;

  bool _loading = true;
  bool _saving = false;
  bool _discharging = false;

  PatientProfile? _profile;

  // 층 코드(빈 침대 조회 파라미터)
  int? _floorStCode;

  // 현재/선택 bed_code
  late int _currentBedCode;
  int? _selectedBedCode;

  bool _bedsLoading = false;
  List<_BedOption> _bedOptions = [];

  // ✅ 수정 가능 필드들 (환자추가와 동일한 컨트롤러/상태)
  final nameCtrl = TextEditingController();
  final ageCtrl = TextEditingController();
  final birthCtrl = TextEditingController();
  DateTime? birthDate;
  String gender = '남';

  final diagnosisCtrl = TextEditingController();
  final doctorCtrl = TextEditingController();
  final nurseCtrl = TextEditingController();
  final allergyCtrl = TextEditingController();
  final significantCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _baseUrl = UrlConfig.serverUrl.toString();
    _currentBedCode = widget.fromBedCode;
    loadData();
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    ageCtrl.dispose();
    birthCtrl.dispose();
    diagnosisCtrl.dispose();
    doctorCtrl.dispose();
    nurseCtrl.dispose();
    allergyCtrl.dispose();
    significantCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<Map<String, String>> _headers() async {
    final token = await _storage.read(key: 'access_token');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.trim().isNotEmpty) 'Authorization': 'Bearer ${token.trim()}',
    };
  }

  Future<void> loadData() async {
    setState(() => _loading = true);
    try {
      await getData();
    } catch (e) {
      _snack('로딩 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> getData() async {
    // 1) 층 코드(스토리지)
    final floorStr = await _storage.read(key: StorageKeys.selectedFloorStCode);
    _floorStCode = int.tryParse((floorStr ?? '').trim());

    // 2) 프로필 조회
    final p = await _fetchPatientProfile(widget.patientCode);
    _profile = p;

    // bed_code 동기화
    final bedFromApi = p.bedCode;
    if (bedFromApi != null && bedFromApi > 0) {
      _currentBedCode = bedFromApi;
    }

    // 3) UI 초기값 세팅
    nameCtrl.text = (p.patientName).trim();
    ageCtrl.text = (p.age?.toString() ?? '').trim();
    gender = (p.gender == 1) ? '여' : '남';

    // birth_date: "890214" 형태 -> DateTime/표시용 yyyy-mm-dd 변환
    final parsedBirth = _parseBirthYYMMDD(p.birthDate ?? '');
    birthDate = parsedBirth;
    birthCtrl.text = parsedBirth != null
        ? '${parsedBirth.year.toString().padLeft(4, '0')}-${parsedBirth.month.toString().padLeft(2, '0')}-${parsedBirth.day.toString().padLeft(2, '0')}'
        : (p.birthDate ?? '').trim();

    diagnosisCtrl.text = (p.diagnosis ?? '').trim();
    doctorCtrl.text = (p.doctor ?? '').trim();
    nurseCtrl.text = (p.nurse ?? '').trim();
    allergyCtrl.text = (p.allergy ?? '').trim();
    significantCtrl.text = (p.significant ?? '').trim();

    // 4) 빈 침대 목록
    await _loadEmptyBeds();

    // 5) 드롭다운 초기값 = 현재 침대
    _selectedBedCode = _currentBedCode;
  }

  // ---------------- API ----------------

  Future<PatientProfile> _fetchPatientProfile(int patientCode) async {
    final uri = Uri.parse('$_baseUrl/api/patient/profile?patient_code=$patientCode');
    final res = await http.get(uri, headers: await _headers());

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('프로필 조회 실패(HTTP ${res.statusCode})');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) throw Exception('프로필 응답 형식 오류');
    if (decoded['code'] != 1) throw Exception((decoded['message'] ?? '프로필 조회 실패').toString());

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) throw Exception('프로필 data 형식 오류');

    return PatientProfile.fromJson(data);
  }

  /// ✅ 명세: GET /api/patient/profile/empty-bed?hospital_st_code={floor}
  /// res: data: [{ hospital_st_code, value: "101호 Bed-7" }, ...]
  Future<void> _loadEmptyBeds() async {
    final floor = _floorStCode;
    if (floor == null) {
      _bedOptions = [];
      return;
    }

    setState(() => _bedsLoading = true);
    try {
      final uri = Uri.parse('$_baseUrl/api/patient/profile/empty-bed?hospital_st_code=$floor');
      final res = await http.get(uri, headers: await _headers());

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('빈 침대 조회 실패(HTTP ${res.statusCode})');
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) throw Exception('빈 침대 응답 형식 오류');
      if (decoded['code'] != 1) throw Exception((decoded['message'] ?? '빈 침대 조회 실패').toString());

      final dataAny = decoded['data'];
      final data = (dataAny is List) ? dataAny : const [];

      final opts = <_BedOption>[];
      for (final x in data) {
        if (x is! Map) continue;

        final bedCode = int.tryParse(x['hospital_st_code']?.toString() ?? '');
        if (bedCode == null) continue;

        final raw = (x['value']?.toString() ?? '').trim(); // "101호 Bed-7"
        final label = raw.isEmpty ? 'bed_code: $bedCode' : raw.replaceFirst(' ', ' · ');

        opts.add(_BedOption(bedCode: bedCode, label: label));
      }

      // ✅ 현재 침대가 목록에 없으면 포함 (Dropdown value mismatch 방지)
      if (_currentBedCode > 0 && !opts.any((e) => e.bedCode == _currentBedCode)) {
        opts.insert(0, _BedOption(bedCode: _currentBedCode, label: '현재 침대 · bed_code: $_currentBedCode'));
      }

      opts.sort((a, b) => a.label.compareTo(b.label));
      setState(() => _bedOptions = opts);
    } finally {
      if (mounted) setState(() => _bedsLoading = false);
    }
  }

  Future<void> _updatePatientProfileBySpec({
    required int patientCode,
    required String patientName,
    required int gender,
    required int age,
    required String birthDate,
    required int bedCode,
    required String nurse,
    required String doctor,
    required String diagnosis,
    String? allergy,
    String? significant,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/patient/profile/update');

    final res = await http.put(
      uri,
      headers: await _headers(),
      body: jsonEncode({
        "patient_code": patientCode,
        "patient_name": patientName,
        "gender": gender,
        "age": age,
        "birth_date": birthDate, // ✅ 명세 키
        "bed_code": bedCode,
        "nurse": nurse,
        "doctor": doctor,
        "diagnosis": diagnosis,
        "allergy": allergy,
        "significant": significant,
      }),
    );

    // ignore: avoid_print
    print('[PUT] $uri -> ${res.statusCode}');
    // ignore: avoid_print
    print('RES: ${res.body}');

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('환자정보 수정 실패(HTTP ${res.statusCode})');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) throw Exception('수정 응답 형식 오류');
    if (decoded['code'] != 1) throw Exception((decoded['message'] ?? '환자정보 수정 실패').toString());
  }

  Future<void> _discharge() async {
    if (_discharging) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // ✅ 디자인만: 화이트톤 + 라운드 + 그린/레드 포인트 유지
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: _cBorder, width: 1),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text('정말 퇴원하겠습니까?', style: TextStyle(fontWeight: FontWeight.w900)),
        content: Text(
          '${nameCtrl.text.trim().isEmpty ? '해당' : nameCtrl.text.trim()} 환자를 퇴원 처리하면 목록에서 제거됩니다.',
          style: const TextStyle(fontWeight: FontWeight.w900, height: 1.4, color: _cText),
        ),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF374151),
              side: const BorderSide(color: _cBorder),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('닫기', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _cRed,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('퇴원', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _discharging = true);
    try {
      final uri = Uri.parse('$_baseUrl/api/patient/profile/delete/${widget.patientCode}');
      final res = await http.delete(uri, headers: await _headers());

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('퇴원 실패(HTTP ${res.statusCode})');
      }

      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['code'] != 1) {
        throw Exception((decoded['message'] ?? '퇴원 실패').toString());
      }

      if (widget.onRefresh != null) await widget.onRefresh!();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _snack('퇴원 실패: $e');
    } finally {
      if (mounted) setState(() => _discharging = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    final bedCode = _selectedBedCode ?? _currentBedCode;
    if (bedCode <= 0) {
      _snack('침대(bed_code)를 선택할 수 없습니다.');
      return;
    }

    // ✅ 컨트롤러에서 값 추출 + 타입 변환
    final patientName = nameCtrl.text.trim();
    final ageInt = int.tryParse(ageCtrl.text.trim());
    final genderInt = (gender == '남') ? 0 : 1;

    if (birthDate == null) {
      _snack('생년월일을 확인해 주세요.');
      return;
    }
    final birthYyMmDd = _birthAsYYMMDD(birthDate!); // "890214"

    final nurse = nurseCtrl.text.trim();
    final doctor = doctorCtrl.text.trim();
    final diagnosis = diagnosisCtrl.text.trim();
    final allergy = allergyCtrl.text.trim().isEmpty ? null : allergyCtrl.text.trim();
    final significant = significantCtrl.text.trim().isEmpty ? null : significantCtrl.text.trim();

    // (필요하면 필수 체크 유지)
    if (patientName.isEmpty || ageInt == null || nurse.isEmpty || doctor.isEmpty || diagnosis.isEmpty) {
      _snack('필수 항목을 확인해 주세요.');
      return;
    }

    setState(() => _saving = true);
    try {
      await _updatePatientProfileBySpec(
        patientCode: widget.patientCode,
        patientName: patientName,
        gender: genderInt,
        age: ageInt,
        birthDate: birthYyMmDd,
        bedCode: bedCode,
        nurse: nurse,
        doctor: doctor,
        diagnosis: diagnosis,
        allergy: allergy,
        significant: significant,
      );

      _currentBedCode = bedCode;

      if (widget.onRefresh != null) await widget.onRefresh!();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _snack('수정 실패: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------- Utils ----------------

  String _birthAsYYMMDD(DateTime d) {
    final yy = (d.year % 100).toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$yy$mm$dd';
  }

  DateTime? _parseBirthYYMMDD(String yymmdd) {
    final s = yymmdd.trim();
    if (s.length != 6) return null;

    final yy = int.tryParse(s.substring(0, 2));
    final mm = int.tryParse(s.substring(2, 4));
    final dd = int.tryParse(s.substring(4, 6));
    if (yy == null || mm == null || dd == null) return null;

    final now = DateTime.now();
    final nowYY = now.year % 100;

    // 간단 규칙: yy <= nowYY 이면 20yy, 아니면 19yy
    final year = (yy <= nowYY) ? 2000 + yy : 1900 + yy;

    try {
      return DateTime(year, mm, dd);
    } catch (_) {
      return null;
    }
  }

  // ---------------- UI (환자추가와 동일 구조/톤) ----------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Dialog(
        backgroundColor: Colors.transparent,
        child: SizedBox(width: 520, height: 220, child: Center(child: CircularProgressIndicator())),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Container(
        width: 720,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _cBorder),
          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 8))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더 (✅ 환자추가 톤 + 퇴원 버튼 추가)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 18, 12),
              child: Row(
                children: [
                  const Text('환자 수정', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _cText)),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _cRed,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onPressed: _discharging ? null : _discharge,
                    child: _discharging
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('퇴원', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _cBorder),

            // 내용
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                child: Column(
                  children: [
                    _Section(
                      title: '기본정보',
                      child: Column(
                        children: [
                          _Row2(
                            left: _TextField(label: '환자명', controller: nameCtrl, requiredMark: true),
                            right: _TextField(
                              label: '나이',
                              controller: ageCtrl,
                              requiredMark: true,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _Row2(
                            left: _Dropdown<String>(
                              label: '성별',
                              value: gender,
                              requiredMark: true,
                              items: const ['남', '여'],
                              onChanged: (v) => setState(() => gender = v),
                            ),
                            right: _DateField(
                              label: '생년월일',
                              controller: birthCtrl,
                              requiredMark: true,
                              onPick: () async {
                                final now = DateTime.now();
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: birthDate ?? DateTime(now.year - 30, 1, 1),
                                  firstDate: DateTime(1900, 1, 1),
                                  lastDate: now,
                                  // ✅ 디자인만: 달력 스타일(화이트톤 + 라운드 + 그린 포인트)
                                  builder: (context, child) {
                                    final base = Theme.of(context);
                                    final cs = base.colorScheme;

                                    return Theme(
                                      data: base.copyWith(
                                        colorScheme: cs.copyWith(
                                          primary: _cGreen,
                                          onPrimary: Colors.white,
                                          surface: Colors.white,
                                          onSurface: _cText,
                                        ),
                                        dialogBackgroundColor: Colors.white,
                                        textButtonTheme: TextButtonThemeData(
                                          style: TextButton.styleFrom(
                                            foregroundColor: const Color(0xFF374151),
                                            textStyle: const TextStyle(fontWeight: FontWeight.w900),
                                          ),
                                        ),
                                        datePickerTheme: DatePickerThemeData(
                                          backgroundColor: Colors.white,
                                          surfaceTintColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                          dividerColor: _cBorder,
                                          headerBackgroundColor: _cGreen,
                                          headerForegroundColor: Colors.white,
                                          weekdayStyle: const TextStyle(fontWeight: FontWeight.w900, color: _cSubText),
                                          dayStyle: const TextStyle(fontWeight: FontWeight.w900, color: _cText),
                                          todayForegroundColor: MaterialStateProperty.all(_cGreen),
                                          todayBorder: BorderSide(color: _cGreen.withOpacity(0.35), width: 1),
                                          dayForegroundColor: MaterialStateProperty.resolveWith((states) {
                                            if (states.contains(MaterialState.selected)) return Colors.white;
                                            return _cText;
                                          }),
                                          dayBackgroundColor: MaterialStateProperty.resolveWith((states) {
                                            if (states.contains(MaterialState.selected)) return _cGreen;
                                            if (states.contains(MaterialState.pressed) || states.contains(MaterialState.hovered)) {
                                              return _cGreenSoft;
                                            }
                                            return Colors.transparent;
                                          }),
                                          dayOverlayColor: MaterialStateProperty.resolveWith((states) {
                                            if (states.contains(MaterialState.pressed) ||
                                                states.contains(MaterialState.hovered) ||
                                                states.contains(MaterialState.focused)) {
                                              return _cGreen.withOpacity(0.10);
                                            }
                                            return Colors.transparent;
                                          }),
                                        ),
                                      ),
                                      child: child ?? const SizedBox.shrink(),
                                    );
                                  },
                                );
                                if (picked == null) return;

                                setState(() {
                                  birthDate = picked;
                                  birthCtrl.text =
                                  '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    _Section(
                      title: '침대 배정',
                      child: Column(
                        children: [
                          if (_floorStCode == null)
                            const Text(
                              '선택된 층이 없습니다. (층 선택 후 다시 시도)',
                              style: TextStyle(color: _cRed, fontWeight: FontWeight.w800),
                            )
                          else if (_bedsLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          else if (_bedOptions.isEmpty)
                              const Text(
                                '빈 침대가 없습니다.',
                                style: TextStyle(color: _cSubText, fontWeight: FontWeight.w800),
                              )
                            else
                              Theme(
                                // ✅ 디자인만: 드롭다운 펼침/hover/press 톤
                                data: Theme.of(context).copyWith(
                                  splashColor: _cGreen.withOpacity(0.10),
                                  highlightColor: _cGreen.withOpacity(0.10),
                                  hoverColor: _cGreenSoft,
                                  focusColor: _cGreenSoft,
                                ),
                                child: DropdownButtonFormField<int>(
                                  value: _selectedBedCode,
                                  items: _bedOptions
                                      .map(
                                        (e) => DropdownMenuItem<int>(
                                      value: e.bedCode,
                                      child: Text(
                                        e.label,
                                        style: const TextStyle(fontWeight: FontWeight.w800),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                      .toList(),
                                  onChanged: (v) => setState(() => _selectedBedCode = v),

                                  // ✅ 디자인만: 드롭다운 필드/팝업 스타일
                                  decoration: _dropdownDeco(),
                                  dropdownColor: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  icon: const Icon(Icons.expand_more_rounded, color: Color(0xFF6B7280)),
                                  style: const TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.w800),
                                ),
                              ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    _Section(
                      title: '진료정보',
                      child: Column(
                        children: [
                          _Row2(
                            left: _TextField(label: '진단명', controller: diagnosisCtrl, requiredMark: true),
                            right: _TextField(label: '주치의', controller: doctorCtrl, requiredMark: true),
                          ),
                          const SizedBox(height: 12),
                          _Row2(
                            left: _TextField(label: '담당 간호사', controller: nurseCtrl, requiredMark: true),
                            right: _TextField(label: '알레르기', controller: allergyCtrl),
                          ),
                          const SizedBox(height: 12),
                          _TextArea(label: '특이사항(필수)', controller: significantCtrl),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: _cBorder),

            // 하단 버튼 (환자추가 동일)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _cGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                        : const Text('저장', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF374151),
                      side: const BorderSide(color: _cBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    ),
                    onPressed: _saving ? null : () => Navigator.pop(context, false),
                    child: const Text('닫기', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Models ----------------

class PatientProfile {
  final int patientCode;
  final String patientName;
  final int gender; // 0 male, 1 female

  final int? age;
  final String? birthDate;
  final int? bedCode;

  final String? nurse;
  final String? doctor;
  final String? diagnosis;
  final String? allergy;
  final String? significant;

  const PatientProfile({
    required this.patientCode,
    required this.patientName,
    required this.gender,
    this.age,
    this.birthDate,
    this.bedCode,
    this.nurse,
    this.doctor,
    this.diagnosis,
    this.allergy,
    this.significant,
  });

  factory PatientProfile.fromJson(Map<String, dynamic> j) {
    return PatientProfile(
      patientCode: int.tryParse(j['patient_code']?.toString() ?? '') ?? -1,
      patientName: (j['patient_name']?.toString() ?? '').trim(),
      gender: int.tryParse(j['gender']?.toString() ?? '') ?? 0,
      age: int.tryParse(j['age']?.toString() ?? ''),
      birthDate: j['birth_date']?.toString(),
      bedCode: int.tryParse(j['bed_code']?.toString() ?? ''),
      nurse: j['nurse']?.toString(),
      doctor: j['doctor']?.toString(),
      diagnosis: j['diagnosis']?.toString(),
      allergy: j['allergy']?.toString(),
      significant: j['significant']?.toString(),
    );
  }
}

class _BedOption {
  final int bedCode;
  final String label;
  const _BedOption({required this.bedCode, required this.label});
}

/* ------------------ 환자추가 동일 스타일 위젯 ------------------ */

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Row2 extends StatelessWidget {
  final Widget left;
  final Widget right;

  const _Row2({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }
}

class _TextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool requiredMark;

  const _TextField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.requiredMark = false,
  });

  @override
  Widget build(BuildContext context) {
    return _FieldShell(
      label: label,
      requiredMark: requiredMark,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: _inputDeco(),
      ),
    );
  }
}

class _TextArea extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const _TextArea({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return _FieldShell(
      label: label,
      child: TextField(
        controller: controller,
        minLines: 3,
        maxLines: 4,
        decoration: _inputDeco(),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool requiredMark;
  final VoidCallback onPick;

  const _DateField({
    required this.label,
    required this.controller,
    required this.onPick,
    this.requiredMark = false,
  });

  @override
  Widget build(BuildContext context) {
    return _FieldShell(
      label: label,
      requiredMark: requiredMark,
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(14),
        child: IgnorePointer(
          child: TextField(
            controller: controller,
            decoration: _inputDeco(suffix: const Icon(Icons.calendar_today_outlined, size: 18)),
          ),
        ),
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final void Function(T v) onChanged;
  final bool requiredMark;

  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.requiredMark = false,
  });

  static const _cGreen = Color(0xFF22C55E);
  static const _cGreenSoft = Color(0xFFECFDF5);

  @override
  Widget build(BuildContext context) {
    return _FieldShell(
      label: label,
      requiredMark: requiredMark,
      child: Theme(
        // ✅ 디자인만: 성별 드롭다운 펼침/hover/press 톤
        data: Theme.of(context).copyWith(
          splashColor: _cGreen.withOpacity(0.10),
          highlightColor: _cGreen.withOpacity(0.10),
          hoverColor: _cGreenSoft,
          focusColor: _cGreenSoft,
        ),
        child: DropdownButtonFormField<T>(
          value: value,
          items: [
            for (final it in items)
              DropdownMenuItem(
                value: it,
                child: Text(it.toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
          ],
          onChanged: (v) {
            if (v == null) return;
            onChanged(v);
          },

          // ✅ 디자인만: 드롭다운 전용 데코/팝업
          decoration: _dropdownDeco(),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(14),
          icon: const Icon(Icons.expand_more_rounded, color: Color(0xFF6B7280)),
          style: const TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _FieldShell extends StatelessWidget {
  final String label;
  final bool requiredMark;
  final Widget child;

  const _FieldShell({
    required this.label,
    required this.child,
    this.requiredMark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
            if (requiredMark) ...[
              const SizedBox(width: 4),
              const Text('*', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w900)),
            ],
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

InputDecoration _inputDeco({Widget? suffix}) {
  return InputDecoration(
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    suffixIcon: suffix,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFF93C5FD), width: 2),
    ),
  );
}

// ✅ 디자인만: 드롭다운 전용(포커스 보더 그린 포인트)
InputDecoration _dropdownDeco({Widget? suffix}) {
  return InputDecoration(
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    suffixIcon: suffix,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFF22C55E), width: 2),
    ),
  );
}
