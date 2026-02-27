import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import '../../../../urlConfig.dart';
import '../../../../storage_keys.dart';

import '../../api/http_helper.dart';
import 'auth_shared_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _storage = FlutterSecureStorage();

  static const _kHospitalCode = 'hospital_code';
  static const _kSelectedWardJson = 'selected_ward_json';

  late final String _front_url;

  final idCtrl = TextEditingController();
  final pwCtrl = TextEditingController();

  bool loading = false;

  @override
  void initState() {
    super.initState();
    _front_url = Urlconfig.serverUrl.toString();
    _bootstrapFromStorage();
  }

  @override
  void dispose() {
    idCtrl.dispose();
    pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrapFromStorage() async {
    try {
      // 선택 병동이 있으면 바로 대시보드로
      final wardJson = await _storage.read(key: _kSelectedWardJson);
      if (wardJson != null && wardJson.isNotEmpty) {
        try {
          final m = jsonDecode(wardJson);
          if (m is Map) {
            final code = m['hospital_st_code']?.toString() ?? '';
            final name = (m['category_name'] ?? '').toString();
            await _storage.write(key: StorageKeys.selectedWardStCode, value: code);
            await _storage.write(key: StorageKeys.selectedWardName, value: name);
          }
        } catch (_) {}

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.go('/dashboard');
        });
        return;
      }

      // 로그인된 상태면 병동 선택으로
      final codeStr = await _storage.read(key: _kHospitalCode);
      if (int.tryParse(codeStr ?? '') != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.go('/ward-select');
        });
      }
    } catch (e) {
      debugPrint('[BOOTSTRAP] error=$e');
    }
  }

  Future<void> _login() async {
    final id = idCtrl.text.trim();
    final pw = pwCtrl.text.trim();

    if (id.isEmpty || pw.isEmpty) {
      _snack('ID와 비밀번호를 입력해 주세요.');
      return;
    }

    setState(() => loading = true);

    try {
      final uri = Uri.parse('$_front_url/api/auth/login');

      final decoded = await HttpHelper.postJson(uri, {
        'hospital_id': id,
        'hospital_password': pw,
      });

      final ok = decoded['code'] == 1;
      if (!ok) {
        final msg = (decoded['message'] ?? '로그인 실패').toString();
        throw Exception(msg);
      }

      final data = decoded['data'];
      if (data is! Map) throw Exception('로그인 응답 data가 비었습니다.');

      final code = int.tryParse(data['hospital_code']?.toString() ?? '');
      if (code == null) throw Exception('병원 코드(hospital_code)를 읽지 못했습니다.');

      await _storage.write(key: _kHospitalCode, value: code.toString());

      if (!mounted) return;
      context.go('/ward-select');
    } catch (e) {
      debugPrint('[LOGIN] error=$e');
      if (!mounted) return;
      setState(() => loading = false);
      _snack('로그인 실패 ID와 PASSWORD를 확인해주세요.');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                const Expanded(flex: 3, child: AuthLeftIntro()),
                const SizedBox(width: 24),
                Expanded(
                  flex: 2,
                  child: AuthCard(
                    title: '로그인',
                    subtitle: '계정 정보를 입력해 주세요.',
                    footer: const Text(
                      '문제가 있으면 관리자에게 문의해 주세요.',
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    child: _LoginForm(
                      onLogin: _login,
                      loading: loading,
                      idCtrl: idCtrl,
                      pwCtrl: pwCtrl,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginForm extends StatefulWidget {
  final Future<void> Function() onLogin;
  final bool loading;
  final TextEditingController idCtrl;
  final TextEditingController pwCtrl;

  const _LoginForm({
    super.key,
    required this.onLogin,
    required this.loading,
    required this.idCtrl,
    required this.pwCtrl,
  });

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  InputDecoration _deco(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF3F4F6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
        borderSide: const BorderSide(color: Color(0xFF93C5FD)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final btnStyle = ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF65C466),
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
      elevation: 0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ID', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF111827))),
        const SizedBox(height: 8),
        TextField(
          controller: widget.idCtrl,
          decoration: _deco('아이디를 입력'),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        const Text('Password', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF111827))),
        const SizedBox(height: 8),
        TextField(
          controller: widget.pwCtrl,
          obscureText: true,
          decoration: _deco('비밀번호를 입력'),
          onSubmitted: (_) => widget.onLogin(),
        ),
        const SizedBox(height: 18),
        ElevatedButton(
          style: btnStyle,
          onPressed: widget.loading ? null : widget.onLogin,
          child: widget.loading
              ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
              : const Text('로그인'),
        ),
      ],
    );
  }
}
