import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import 'package:mfps/url_config.dart';
import 'package:mfps/storage_keys.dart';

// ✅ 쿠키 세션 유지되는 http helper
import 'package:mfps/api/http_helper.dart';

enum SettingsSection {
  accountInfo, // 회원정보
  password, // 비밀번호 변경
  withdraw, // 회원 탈퇴
  mySettings, // 내 설정
  systemInfo, // 시스템 정보
  wardManage, // 병동 관리
}

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  static const _storage = FlutterSecureStorage();

  // ✅ (추가) 다이얼로그 내부에서만 SnackBar 띄우기 위한 키
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  late final String _baseUrl;
  SettingsSection _section = SettingsSection.accountInfo;

  bool _loading = false;

  // 병원 정보(회원정보 화면)
  int? _hospitalCode;
  String _hospitalId = '';
  String _hospitalName = '';

  // 병동 관리
  bool _wardsLoading = false;
  List<_WardItem> _wards = [];

  // 비밀번호 변경
  final _newPwCtrl = TextEditingController();
  final _newPwVerifyCtrl = TextEditingController();
  bool _pwSaving = false;

  @override
  void initState() {
    super.initState();
    _baseUrl = UrlConfig.serverUrl.toString();
    loadData(); // 기본: 회원정보 탭 데이터 로드
  }

  @override
  void dispose() {
    _newPwCtrl.dispose();
    _newPwVerifyCtrl.dispose();
    super.dispose();
  }

  // ✅ (수정) 반드시 다이얼로그 내부 ScaffoldMessenger로 띄우기
  void _snack(String msg) {
    if (!mounted) return;

    final messenger = _messengerKey.currentState;
    if (messenger == null) return;

    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(12),
        ),
      );
  }

  Future<void> loadData() async {
    if (mounted) setState(() => _loading = true);
    try {
      await getData();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> getData() async {
    // hospital_code 읽기
    final codeStr = await _storage.read(key: StorageKeys.hospitalCode);
    final code = int.tryParse((codeStr ?? '').trim());
    _hospitalCode = code;

    // 회원정보 탭 기본 로드
    if (_section == SettingsSection.accountInfo) {
      await _loadAccountInfo();
    }

    // 병동관리 탭이면 병동 로드
    if (_section == SettingsSection.wardManage) {
      await _loadWards();
    }
  }

  /// ✅ 쿠키 세션 기반 GET (HttpHelper 사용)
  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    try {
      final decoded = await HttpHelper.getJsonAllowError(uri);

      // ignore: avoid_print
      print('[GET] $uri -> ok');
      // ignore: avoid_print
      print('RES: ${jsonEncode(decoded)}');

      return decoded;
    } catch (e) {
      // ignore: avoid_print
      print('[GET] $uri -> error: $e');
      return null;
    }
  }

  /// ✅ 쿠키 세션 기반 PUT/DELETE/... (HttpHelper 사용)
  Future<Map<String, dynamic>?> _sendJson(
      String method,
      Uri uri, {
        Map<String, dynamic>? body,
      }) async {
    try {
      final decoded = await HttpHelper.sendJsonAllowError(
        method,
        uri,
        body: body,
      );

      // ignore: avoid_print
      print('[$method] $uri -> ok');
      // ignore: avoid_print
      print('REQ: ${body == null ? '' : jsonEncode(body)}');
      // ignore: avoid_print
      print('RES: ${jsonEncode(decoded)}');

      return decoded;
    } catch (e) {
      // ignore: avoid_print
      print('[$method] $uri -> error: $e');
      return null;
    }
  }

  Future<void> _logout() async {
    if (!mounted) return;

    await _storage.delete(key: StorageKeys.selectedWardStCode);
    await _storage.delete(key: StorageKeys.selectedWardName);
    await _storage.delete(key: StorageKeys.selectedFloorStCode);
    await _storage.delete(key: StorageKeys.floorLabel);

    Navigator.pop(context);
    GoRouter.of(context).go('/login');
  }

  Future<void> _loadAccountInfo() async {
    final code = _hospitalCode;
    if (code == null) {
      _hospitalId = '';
      _hospitalName = '';
      return;
    }

    final uri = Uri.parse('$_baseUrl/api/auth/email?hospital_code=$code');
    final decoded = await _getJson(uri);
    if (decoded == null) return;

    if (decoded['code'] != 1) {
      // ignore: avoid_print
      print('accountInfo code!=1: ${decoded['message']}');
      return;
    }

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) return;

    if (!mounted) return;
    setState(() {
      _hospitalId = (data['hospital_id']?.toString() ?? '').trim();
      _hospitalName = (data['hospital_name']?.toString() ?? '').trim();
    });
  }

  Future<void> _loadWards() async {
    final code = _hospitalCode;
    if (code == null) {
      if (mounted) setState(() => _wards = []);
      return;
    }

    if (mounted) setState(() => _wardsLoading = true);

    final uri =
    Uri.parse('$_baseUrl/api/hospital/structure/part?hospital_code=$code');
    final decoded = await _getJson(uri);

    if (decoded == null || decoded['code'] != 1) {
      if (mounted) setState(() => _wardsLoading = false);
      return;
    }

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      if (mounted) setState(() => _wardsLoading = false);
      return;
    }

    final parts = (data['parts'] as List?) ?? [];
    final list = <_WardItem>[];

    for (final e in parts) {
      if (e is! Map) continue;
      final st = int.tryParse(e['hospital_st_code']?.toString() ?? '');
      final name = (e['category_name']?.toString() ?? '').trim();
      final sort = int.tryParse(e['sort_order']?.toString() ?? '') ?? 0;
      if (st == null) continue;
      list.add(_WardItem(hospitalStCode: st, categoryName: name, sortOrder: sort));
    }

    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    if (!mounted) return;
    setState(() {
      _wards = list;
      _wardsLoading = false;
    });
  }

  Future<void> _changePassword() async {
    final newPw = _newPwCtrl.text.trim();
    final newPwV = _newPwVerifyCtrl.text.trim();

    if (newPw.isEmpty || newPwV.isEmpty) {
      _snack('새 비밀번호와 확인을 입력해 주세요.');
      return;
    }
    if (newPw != newPwV) {
      _snack('새 비밀번호와 확인이 일치하지 않습니다.');
      return;
    }

    if (mounted) setState(() => _pwSaving = true);

    try {
      final uri = Uri.parse('$_baseUrl/api/auth/email/update');
      final decoded = await _sendJson('PUT', uri, body: {
        'hospital_new_password': newPw,
        'hospital_new_password_verify': newPwV,
      });

      if (decoded == null) {
        _snack('비밀번호 변경 요청 실패');
        return;
      }

      if (decoded['code'] == 1) {
        _snack('비밀번호가 변경되었습니다.');
        _newPwCtrl.clear();
        _newPwVerifyCtrl.clear();
      } else {
        _snack((decoded['message'] ?? '비밀번호 변경 실패').toString());
      }
    } finally {
      if (mounted) setState(() => _pwSaving = false);
    }
  }

  Future<void> _withdraw() async {
    final code = _hospitalCode;
    if (code == null) {
      _snack('병원 코드가 없습니다. 다시 로그인해 주세요.');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        elevation: 2,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        title: const Text(
          '회원 탈퇴',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Color(0xFF111827),
          ),
        ),
        content: const Text(
          '정말 탈퇴하시겠습니까?\n탈퇴 후에는 계정을 복구할 수 없습니다.',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: Color(0xFF374151),
            height: 1.35,
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF374151),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('탈퇴'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final uri = Uri.parse('$_baseUrl/api/auth/email/delete/$code');
    final decoded = await _sendJson('DELETE', uri);

    if (decoded == null) {
      _snack('탈퇴 요청 실패');
      return;
    }

    if (decoded['code'] == 1) {
      _snack('탈퇴가 완료되었습니다.');
      await _storage.deleteAll();
      if (!mounted) return;
      Navigator.pop(context);
      GoRouter.of(context).go('/login');
    } else {
      _snack((decoded['message'] ?? '탈퇴 실패').toString());
    }
  }

  Future<void> _renameWard(_WardItem w) async {
    final nextName = await _showTextDialog(
      context,
      title: '병동 이름 수정',
      initial: w.categoryName,
      hint: '병동 이름을 입력',
    );
    if (nextName == null) return;

    final uri = Uri.parse('$_baseUrl/api/hospital/structure/update');

    final decoded = await _sendJson('PUT', uri, body: {
      'hopital_st_code': w.hospitalStCode,
      'hospital_st_code': w.hospitalStCode,
      'category_name': nextName,
    });

    if (decoded == null) {
      _snack('병동 이름 수정 실패');
      return;
    }
    if (decoded['code'] == 1) {
      _snack('병동 이름이 변경되었습니다: $nextName');
      await _loadWards();
    } else {
      _snack((decoded['message'] ?? '병동 이름 수정 실패').toString());
    }
  }

  Future<void> _deleteWard(_WardItem w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        elevation: 2,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        title: const Text(
          '병동 삭제',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Color(0xFF111827),
          ),
        ),
        content: Text(
          '정말 "${w.categoryName}" 병동을 삭제하시겠습니까?',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: Color(0xFF374151),
            height: 1.35,
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF374151),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final uri =
    Uri.parse('$_baseUrl/api/hospital/structure/delete/${w.hospitalStCode}');
    final decoded = await _sendJson('DELETE', uri);

    if (decoded == null) {
      _snack('병동 삭제 실패');
      return;
    }
    if (decoded['code'] == 1) {
      _snack('병동이 삭제되었습니다: ${w.categoryName}');
      await _loadWards();
    } else {
      _snack((decoded['message'] ?? '병동 삭제 실패').toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      // ✅ (추가) 다이얼로그 내부 스낵바 영역 고정
      child: ScaffoldMessenger(
        key: _messengerKey,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Container(
            width: 1120,
            height: 720,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
                  child: Row(
                    children: [
                      const Text('설정',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Row(
                    children: [
                      // 좌측 메뉴
                      Container(
                        width: 300,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(right: BorderSide(color: Color(0xFFE5E7EB))),
                        ),
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          children: [
                            const _MenuTitle('회원 관리'),
                            _MenuItem(
                              title: '회원정보',
                              icon: Icons.badge_outlined,
                              selected: _section == SettingsSection.accountInfo,
                              onTap: () async {
                                setState(() => _section = SettingsSection.accountInfo);
                                await loadData();
                              },
                            ),
                            _MenuItem(
                              title: '비밀번호 변경',
                              icon: Icons.lock_outline,
                              selected: _section == SettingsSection.password,
                              onTap: () => setState(() => _section = SettingsSection.password),
                            ),
                            _MenuItem(
                              title: '회원 탈퇴',
                              icon: Icons.delete_outline,
                              danger: true,
                              selected: _section == SettingsSection.withdraw,
                              onTap: () => setState(() => _section = SettingsSection.withdraw),
                            ),
                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            const SizedBox(height: 10),
                            const _MenuTitle('병동 관리'),
                            _MenuItem(
                              title: '병동 관리',
                              icon: Icons.apartment_outlined,
                              selected: _section == SettingsSection.wardManage,
                              onTap: () async {
                                setState(() => _section = SettingsSection.wardManage);
                                await loadData();
                              },
                            ),
                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            const SizedBox(height: 10),
                            const _MenuTitle('내 설정'),
                            _MenuItem(
                              title: '내 설정',
                              icon: Icons.tune,
                              selected: _section == SettingsSection.mySettings,
                              onTap: () => setState(() => _section = SettingsSection.mySettings),
                            ),
                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            const SizedBox(height: 10),
                            const _MenuTitle('시스템 정보'),
                            _MenuItem(
                              title: '앱 버전',
                              icon: Icons.info_outline,
                              selected: _section == SettingsSection.systemInfo,
                              onTap: () => setState(() => _section = SettingsSection.systemInfo),
                            ),
                          ],
                        ),
                      ),
                      // 우측 내용
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: _loading
                              ? const Center(child: CircularProgressIndicator())
                              : _buildContent(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_section) {
      case SettingsSection.accountInfo:
        return _AccountInfoView(
          hospitalCode: _hospitalCode,
          hospitalId: _hospitalId,
          hospitalName: _hospitalName,
          onReload: loadData,
          onLogout: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: const Color(0xFFFFFFFF),
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                elevation: 2,
                insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                title: const Text(
                  '로그아웃',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: Color(0xFF111827),
                  ),
                ),
                content: const Text(
                  '로그아웃 하시겠습니까?',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Color(0xFF374151),
                    height: 1.35,
                  ),
                ),
                actions: [
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF374151),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('취소'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF22C55E),
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('로그아웃'),
                  ),
                ],
              ),
            );

            if (ok == true) await _logout();
          },
        );

      case SettingsSection.password:
        return _PasswordChangeView(
          newPwCtrl: _newPwCtrl,
          newPwVerifyCtrl: _newPwVerifyCtrl,
          saving: _pwSaving,
          onSubmit: _changePassword,
        );

      case SettingsSection.withdraw:
        return _WithdrawView(onConfirm: _withdraw);

      case SettingsSection.mySettings:
        return const _MySettingsView();

      case SettingsSection.systemInfo:
        return const _SystemInfoView();

      case SettingsSection.wardManage:
        return _WardManageView(
          hospitalCode: _hospitalCode,
          loading: _wardsLoading,
          wards: _wards,
          onReload: _loadWards,
          onRename: _renameWard,
          onDelete: _deleteWard,
        );
    }
  }

  static Future<String?> _showTextDialog(
      BuildContext context, {
        required String title,
        String? initial,
        required String hint,
      }) async {
    final ctrl = TextEditingController(text: initial ?? '');

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        elevation: 2,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Color(0xFF111827),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: hint,
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF22C55E), width: 1.6),
                ),
              ),
              onSubmitted: (_) {
                final v = ctrl.text.trim();
                if (v.isEmpty) return;
                Navigator.pop(ctx, v);
              },
            ),
            const SizedBox(height: 4),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '이름을 입력한 뒤 저장을 눌러주세요.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF374151),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isEmpty) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }
}

/* -------------------- 병동 관리(병동 추가 버튼 삭제 버전) -------------------- */

class _WardManageView extends StatelessWidget {
  final int? hospitalCode;
  final bool loading;
  final List<_WardItem> wards;

  final Future<void> Function() onReload;
  final Future<void> Function(_WardItem w) onRename;
  final Future<void> Function(_WardItem w) onDelete;

  const _WardManageView({
    required this.hospitalCode,
    required this.loading,
    required this.wards,
    required this.onReload,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: '병동 관리',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: const [
              Text(
                '병동 목록을 관리합니다.',
                style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w700),
              ),
              Spacer(),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: () {
              if (hospitalCode == null) {
                return const Center(
                  child: Text('병원 코드가 없습니다.\n다시 로그인해 주세요.', textAlign: TextAlign.center),
                );
              }
              if (loading) return const Center(child: CircularProgressIndicator());
              if (wards.isEmpty) {
                return const Center(
                  child: Text('등록된 병동이 없습니다.', style: TextStyle(fontWeight: FontWeight.w800)),
                );
              }

              return ListView.separated(
                itemCount: wards.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final w = wards[i];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.apartment_outlined, color: Color(0xFF374151)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            w.categoryName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '이름 수정',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => onRename(w),
                        ),
                        IconButton(
                          tooltip: '삭제',
                          icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                          onPressed: () => onDelete(w),
                        ),
                      ],
                    ),
                  );
                },
              );
            }(),
          ),
        ],
      ),
    );
  }
}

/* -------------------- 이하 UI 공통 -------------------- */

class _WardItem {
  final int hospitalStCode;
  final String categoryName;
  final int sortOrder;

  const _WardItem({
    required this.hospitalStCode,
    required this.categoryName,
    required this.sortOrder,
  });
}

class _MenuTitle extends StatelessWidget {
  final String text;
  const _MenuTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: Color(0xFF6B7280),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final bool danger;
  final VoidCallback onTap;

  const _MenuItem({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? const Color(0xFFF3F4F6) : Colors.transparent;
    final fg = danger
        ? const Color(0xFFEF4444)
        : (selected ? const Color(0xFF111827) : const Color(0xFF374151));

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: selected ? Border.all(color: const Color(0xFFE5E7EB)) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w800, color: fg),
              ),
            ),
            if (selected) const Icon(Icons.chevron_right, color: Color(0xFF6B7280)),
          ],
        ),
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _PanelCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _AccountInfoView extends StatelessWidget {
  final int? hospitalCode;
  final String hospitalId;
  final String hospitalName;

  final Future<void> Function() onReload;
  final Future<void> Function() onLogout;

  const _AccountInfoView({
    required this.hospitalCode,
    required this.hospitalId,
    required this.hospitalName,
    required this.onReload,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: '회원정보',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(label: '아이디', value: hospitalId.isEmpty ? '-' : hospitalId),
          const SizedBox(height: 10),
          _InfoRow(label: '병원명', value: hospitalName.isEmpty ? '-' : hospitalName),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              const Spacer(),
              OutlinedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('로그아웃'),
                onPressed: () async {
                  const storage = FlutterSecureStorage();

                  await storage.delete(key: 'hospital_code');
                  await storage.delete(key: 'selected_ward_json');
                  await storage.delete(key: StorageKeys.selectedWardStCode);
                  await storage.delete(key: StorageKeys.selectedWardName);
                  await storage.delete(key: StorageKeys.selectedFloorStCode);
                  await storage.delete(key: StorageKeys.floorLabel);

                  await onLogout();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PasswordChangeView extends StatelessWidget {
  final TextEditingController newPwCtrl;
  final TextEditingController newPwVerifyCtrl;
  final bool saving;
  final Future<void> Function() onSubmit;

  const _PasswordChangeView({
    required this.newPwCtrl,
    required this.newPwVerifyCtrl,
    required this.saving,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: '비밀번호 변경',
      child: Column(
        children: [
          const SizedBox(height: 12),
          TextField(
            controller: newPwCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: '새 비밀번호',
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: newPwVerifyCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: '새 비밀번호 확인',
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: saving ? null : onSubmit,
              child: saving
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Text('변경'),
            ),
          ),
        ],
      ),
    );
  }
}

class _WithdrawView extends StatelessWidget {
  final Future<void> Function() onConfirm;
  const _WithdrawView({required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: '회원 탈퇴',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '탈퇴 시 계정 및 데이터가 삭제될 수 있습니다.\n이 작업은 되돌릴 수 없습니다.',
            style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
              onPressed: onConfirm,
              child: const Text('탈퇴하기'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MySettingsView extends StatelessWidget {
  const _MySettingsView();

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: '내 설정',
      child: Column(
        children: const [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.tune),
            title: Text('설정 항목 준비중', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('추가 설정이 들어갈 예정입니다.'),
          ),
        ],
      ),
    );
  }
}

class _SystemInfoView extends StatelessWidget {
  const _SystemInfoView();

  @override
  Widget build(BuildContext context) {
    const appVersion = '1.0.0';

    return _PanelCard(
      title: '시스템 정보',
      child: Column(
        children: const [
          _InfoRow(label: '앱 버전', value: appVersion),
          SizedBox(height: 10),
          _InfoRow(label: '서버 상태', value: '정상'),
          SizedBox(height: 10),
          _InfoRow(label: '최근 동기화', value: '방금 전'),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }
}
