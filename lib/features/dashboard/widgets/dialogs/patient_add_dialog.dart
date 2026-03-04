import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'package:mfps/url_config.dart';
import 'package:mfps/storage_keys.dart';

class PatientAddDialog extends StatefulWidget {
  final int? prefillBedCode; // 침대 hospital_st_code (bed_code)
  final String? prefillRoomLabel; // (미사용) 표시용
  final String? prefillBedLabel; // (미사용) 표시용

  const PatientAddDialog({
    super.key,
    this.prefillBedCode,
    this.prefillRoomLabel,
    this.prefillBedLabel,
  });

  @override
  State<PatientAddDialog> createState() => _PatientAddDialogState();
}

class _PatientAddDialogState extends State<PatientAddDialog> {
  // =========================
  // Storage / Theme Const
  // =========================
  static const _storage = FlutterSecureStorage();

  static const _cBorder = Color(0xFFE5E7EB);
  static const _cText = Color(0xFF111827);
  static const _cSubText = Color(0xFF6B7280);
  static const _cGreen = Color(0xFF22C55E);

  // ✅ 드롭다운/달력 톤 보조
  static const _cGreenSoft = Color(0xFFECFDF5); // 연한 그린
  static const _cGray900 = Color(0xFF111827);
  static const _cGray700 = Color(0xFF374151);
  static const _cGray500 = Color(0xFF6B7280);

  String get _baseUrl => UrlConfig.serverUrl;

  // =========================
  // Controllers (기본/진료)
  // =========================
  final nameCtrl = TextEditingController();
  final ageCtrl = TextEditingController();
  final birthCtrl = TextEditingController();

  final diagnosisCtrl = TextEditingController();
  final doctorCtrl = TextEditingController();
  final nurseCtrl = TextEditingController();
  final allergyCtrl = TextEditingController();
  final significantCtrl = TextEditingController();

  // =========================
  // Form State
  // =========================
  String gender = '남';
  DateTime? birthDate;
  bool saving = false;

  // =========================
  // Empty Bed List (단일 드롭박스)
  // =========================
  bool loadingBeds = true;
  int? floorStCode; // 스토리지에서 읽은 "층 hospital_st_code"
  List<_BedOption> bedOptions = [];
  int? selectedBedCode;

  // =========================
  // Lifecycle
  // =========================
  @override
  void initState() {
    super.initState();
    _initBeds();
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

  // =========================
  // Network Helpers
  // =========================
  Future<Map<String, String>> _authHeaders() async {
    final token = await _storage.read(key: 'access_token');
    final headers = <String, String>{'Content-Type': 'application/json'};

    final t = token?.trim();
    if (t != null && t.isNotEmpty) {
      headers['Authorization'] = 'Bearer $t';
    }
    return headers;
  }

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    final res = await http.get(uri, headers: await _authHeaders());
    final decoded = jsonDecode(res.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  Future<Map<String, dynamic>?> _postJson(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    final res = await http.post(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode(body),
    );
    final decoded = jsonDecode(res.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  // =========================
  // Init: Floor from storage -> Empty beds API
  // =========================
  Future<void> _initBeds() async {
    setState(() => loadingBeds = true);

    final stStr = await _storage.read(key: StorageKeys.selectedFloorStCode);
    floorStCode = int.tryParse((stStr ?? '').trim());

    if (floorStCode == null) {
      setState(() {
        bedOptions = [];
        selectedBedCode = null;
        loadingBeds = false;
      });
      return;
    }

    await _loadEmptyBeds(floorStCode!);
  }

  Future<void> _loadEmptyBeds(int floorCode) async {
    setState(() => loadingBeds = true);

    try {
      final uri = Uri.parse(
        '$_baseUrl/api/patient/profile/empty-bed?hospital_st_code=$floorCode',
      );

      final decoded = await _getJson(uri);
      if (decoded == null || decoded['code'] != 1) {
        setState(() {
          bedOptions = [];
          selectedBedCode = null;
          loadingBeds = false;
        });
        return;
      }

      final dataList = _asList(decoded['data']);
      final opts = <_BedOption>[];

      // Dropdown value는 중복되면 에러나서, bedCode 중복은 일단 제거
      final seen = <int>{};

      for (final itAny in dataList) {
        final it = _asMap(itAny);
        if (it == null) continue;

        final bedCode = _toInt(it['hospital_st_code']);
        if (bedCode == null) continue;

        if (seen.contains(bedCode)) continue;
        seen.add(bedCode);

        final label = _toStr(it['value']); // 예: "101호 Bed-7"
        opts.add(_BedOption(bedCode: bedCode, label: label));
      }

      // 정렬: "101호 Bed-7" 기준(호실 숫자 -> 침대 숫자)
      opts.sort((a, b) {
        final ad = _allDigits(a.label);
        final bd = _allDigits(b.label);
        final ar = ad.isNotEmpty ? ad[0] : 0;
        final br = bd.isNotEmpty ? bd[0] : 0;
        if (ar != br) return ar.compareTo(br);
        final ab = ad.length > 1 ? ad[1] : 0;
        final bb = bd.length > 1 ? bd[1] : 0;
        return ab.compareTo(bb);
      });

      int? initialBed;
      if (widget.prefillBedCode != null &&
          opts.any((e) => e.bedCode == widget.prefillBedCode)) {
        initialBed = widget.prefillBedCode;
      } else {
        initialBed = opts.isNotEmpty ? opts.first.bedCode : null;
      }

      setState(() {
        bedOptions = opts;
        selectedBedCode = initialBed;
        loadingBeds = false;
      });
    } catch (_) {
      setState(() {
        bedOptions = [];
        selectedBedCode = null;
        loadingBeds = false;
      });
    }
  }

  List<int> _allDigits(String s) {
    final ms = RegExp(r'\d+').allMatches(s);
    return ms.map((m) => int.tryParse(m.group(0) ?? '') ?? 0).toList();
  }

  // =========================
  // Save
  // =========================
  Future<void> _save() async {
    final name = nameCtrl.text.trim();
    final age = int.tryParse(ageCtrl.text.trim());
    final diag = diagnosisCtrl.text.trim();
    final doctor = doctorCtrl.text.trim();
    final nurse = nurseCtrl.text.trim();
    final allergy = allergyCtrl.text.trim();
    final significant = significantCtrl.text.trim(); // ✅ 원래대로 (기능 유지)
    final bedCode = selectedBedCode;

    // 기존 동작 유지(검증 항목/문구)
    if (name.isEmpty ||
        age == null ||
        birthDate == null ||
        diag.isEmpty ||
        doctor.isEmpty) {
      _snack('필수 항목(환자명/나이/생년월일/진단명/주치의/담당 간호사)을 확인해 주세요.');
      return;
    }
    if (bedCode == null) {
      _snack('배정할 침대를 선택할 수 없습니다. (빈 침대 없음)');
      return;
    }

    final birthYyMmDd = _birthAsYYMMDD(birthDate!);
    final genderInt = (gender == '남') ? 0 : 1;

    setState(() => saving = true);

    try {
      final uri = Uri.parse('$_baseUrl/api/patient/profile');

      final decoded = await _postJson(uri, {
        "patient_name": name,
        "gender": genderInt,
        "age": age,
        "birth_date": birthYyMmDd,
        "bed_code": bedCode,
        "nurse": nurse,
        "doctor": doctor,
        "diagnosis": diag,
        "allergy": allergy,
        "significant": significant,
      });

      if (decoded == null || decoded['code'] != 1) {
        _snack((decoded?['message'] ?? '환자 추가 실패').toString());
        setState(() => saving = false);
        return;
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _snack('요청 실패: $e');
      setState(() => saving = false);
    }
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    final bedItems = bedOptions
        .map(
          (e) => DropdownMenuItem<int>(
            value: e.bedCode,
            child: Text(
              e.label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        )
        .toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Container(
        width: 720,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _cBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 18, 12),
              child: Row(
                children: const [
                  Text(
                    '환자 추가',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: _cText,
                    ),
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
                    _buildBasicSection(),
                    const SizedBox(height: 14),
                    _buildBedOnlySection(bedItems: bedItems),
                    const SizedBox(height: 14),
                    _buildMedicalSection(),
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: _cBorder),

            // 하단 버튼
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 14,
                      ),
                    ),
                    onPressed: saving ? null : _save,
                    child: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '추가',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF374151),
                      side: const BorderSide(color: _cBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                    ),
                    onPressed: saving
                        ? null
                        : () => Navigator.pop(context, false),
                    child: const Text(
                      '닫기',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicSection() {
    return _Section(
      title: '기본정보',
      child: Column(
        children: [
          _Row2(
            left: _TextField(
              label: '환자명',
              controller: nameCtrl,
              requiredMark: true,
            ),
            right: _TextField(
              label: '나이',
              controller: ageCtrl,
              keyboardType: TextInputType.number,
              requiredMark: true,
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
                  locale: const Locale('ko', 'KR'),
                  builder: (context, child) {
                    final base = Theme.of(context);
                    final cs = base.colorScheme;

                    // ✅ 달력 스타일(화이트톤 + 라운드 + 그린 포인트)
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
                            foregroundColor: _cGray700,
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        datePickerTheme: DatePickerThemeData(
                          backgroundColor: Colors.white,
                          surfaceTintColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          dividerColor: _cBorder,

                          headerBackgroundColor: _cGreen,
                          headerForegroundColor: Colors.white,

                          weekdayStyle: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: _cSubText,
                          ),
                          dayStyle: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: _cText,
                          ),

                          todayForegroundColor: MaterialStateProperty.all(
                            _cGreen,
                          ),
                          todayBorder: BorderSide(
                            color: _cGreen.withOpacity(0.35),
                            width: 1,
                          ),

                          dayForegroundColor: MaterialStateProperty.resolveWith(
                            (states) {
                              if (states.contains(MaterialState.selected))
                                return Colors.white;
                              return _cText;
                            },
                          ),
                          dayBackgroundColor: MaterialStateProperty.resolveWith(
                            (states) {
                              if (states.contains(MaterialState.selected))
                                return _cGreen;
                              if (states.contains(MaterialState.pressed) ||
                                  states.contains(MaterialState.hovered)) {
                                return _cGreenSoft;
                              }
                              return Colors.transparent;
                            },
                          ),
                          dayOverlayColor: MaterialStateProperty.resolveWith((
                            states,
                          ) {
                            if (states.contains(MaterialState.pressed) ||
                                states.contains(MaterialState.hovered) ||
                                states.contains(MaterialState.focused)) {
                              return _cGreen.withOpacity(0.10);
                            }
                            return Colors.transparent;
                          }),
                        ),
                      ),
                      // ── 달력 크기 조절: width / height 값을 바꾸세요 ──
                      child: SizedBox(width: 600, height: 520, child: child),
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
    );
  }

  Widget _buildBedOnlySection({required List<DropdownMenuItem<int>> bedItems}) {
    return _Section(
      title: '침대 배정',
      child: Column(
        children: [
          if (floorStCode == null)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '선택된 층이 없습니다. (층 선택 후 다시 시도)',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          else if (loadingBeds)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (bedOptions.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '빈 침대가 없습니다.',
                style: TextStyle(color: _cSubText, fontWeight: FontWeight.w800),
              ),
            )
          else
            _FieldShell(
              label: '침대',
              requiredMark: true,
              child: Theme(
                // ✅ 드롭다운 펼쳤을 때 hover/press 느낌(화이트+그린)
                data: Theme.of(context).copyWith(
                  splashColor: _cGreen.withOpacity(0.10),
                  highlightColor: _cGreen.withOpacity(0.10),
                  hoverColor: _cGreenSoft,
                  focusColor: _cGreenSoft,
                ),
                child: DropdownButtonFormField<int>(
                  value: selectedBedCode,
                  items: bedItems,
                  onChanged: (v) => setState(() => selectedBedCode = v),

                  dropdownColor: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  icon: const Icon(
                    Icons.expand_more_rounded,
                    color: Color(0xFF6B7280),
                  ),
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w800,
                  ),

                  // ✅ 드롭다운 필드 포커스 보더만 그린 포인트
                  decoration: _dropdownDeco(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMedicalSection() {
    return _Section(
      title: '진료정보',
      child: Column(
        children: [
          _Row2(
            left: _TextField(
              label: '진단명',
              controller: diagnosisCtrl,
              requiredMark: true,
            ),
            right: _TextField(
              label: '주치의',
              controller: doctorCtrl,
              requiredMark: true,
            ),
          ),
          const SizedBox(height: 12),
          _Row2(
            left: _TextField(
              label: '담당 간호사',
              controller: nurseCtrl,
              requiredMark: true,
            ),
            right: _TextField(label: '알레르기', controller: allergyCtrl),
          ),
          const SizedBox(height: 12),
          _TextArea(label: '특이사항(필수)', controller: significantCtrl),
        ],
      ),
    );
  }

  // =========================
  // Small Utils
  // =========================
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _birthAsYYMMDD(DateTime d) {
    final yy = (d.year % 100).toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$yy$mm$dd';
  }

  static List _asList(dynamic v) => (v is List) ? v : const [];
  static Map<String, dynamic>? _asMap(dynamic v) =>
      (v is Map) ? Map<String, dynamic>.from(v) : null;
  static String _toStr(dynamic v) => (v ?? '').toString().trim();
  static int? _toInt(dynamic v) => int.tryParse((v ?? '').toString().trim());
}

// =========================
// Option Models
// =========================
class _BedOption {
  final int bedCode; // hospital_st_code (bed_code)
  final String label; // value: "101호 Bed-7"
  const _BedOption({required this.bedCode, required this.label});
}

/* ------------------ 스타일 위젯(대시보드 톤) ------------------ */

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
  final bool requiredMark;

  const _TextArea({
    required this.label,
    required this.controller,
    this.requiredMark = false,
  });

  @override
  Widget build(BuildContext context) {
    return _FieldShell(
      label: label,
      requiredMark: requiredMark,
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
            decoration: _inputDeco(
              suffix: const Icon(Icons.calendar_today_outlined, size: 18),
            ),
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
        // ✅ 성별 드롭다운도 펼쳤을 때 원하는 톤 적용
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
                child: Text(
                  it.toString(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
          ],
          onChanged: (v) {
            if (v == null) return;
            onChanged(v);
          },
          decoration: _dropdownDeco(),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(14),
          icon: const Icon(Icons.expand_more_rounded, color: Color(0xFF6B7280)),
          style: const TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w800,
          ),
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
              const Text(
                '*',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w900,
                ),
              ),
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

// ✅ 드롭다운 전용(포커스 보더만 그린 포인트)
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
