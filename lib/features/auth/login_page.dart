import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:mfps/url_config.dart';
import 'package:mfps/storage_keys.dart';

import 'package:mfps/api/http_helper.dart';
import 'auth_shared_widgets.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const _storage = FlutterSecureStorage();

  static const _hospitalCodeStorageKey = 'hospital_code';
  static const _selectedWardStorageKey = 'selected_ward_json';

  late final String _frontUrl;

  final hospitalIdController = TextEditingController();
  final passwordController = TextEditingController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _frontUrl = UrlConfig.serverUrl.toString();
    _bootstrapFromStorage();
  }

  @override
  void dispose() {
    hospitalIdController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _bootstrapFromStorage() async {
    try {
      // 선택 병동이 있으면 바로 대시보드로
      final selectedWardJson = await _storage.read(
        key: _selectedWardStorageKey,
      );
      if (selectedWardJson != null && selectedWardJson.isNotEmpty) {
        try {
          final selectedWardMap = jsonDecode(selectedWardJson);
          if (selectedWardMap is Map) {
            final wardCode =
                selectedWardMap['hospital_st_code']?.toString() ?? '';
            final wardName = (selectedWardMap['category_name'] ?? '')
                .toString();
            await _storage.write(
              key: StorageKeys.selectedWardStCode,
              value: wardCode,
            );
            await _storage.write(
              key: StorageKeys.selectedWardName,
              value: wardName,
            );
          }
        } catch (_) {}

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.go('/dashboard');
        });
        return;
      }

      // 로그인된 상태면 병동 선택으로
      final storedHospitalCode = await _storage.read(
        key: _hospitalCodeStorageKey,
      );
      if (int.tryParse(storedHospitalCode ?? '') != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.go('/ward-select');
        });
      }
    } catch (e) {
      debugPrint('[BOOTSTRAP] error=$e');
    }
  }

  Future<void> _handleLogin() async {
    final hospitalId = hospitalIdController.text.trim();
    final hospitalPassword = passwordController.text.trim();

    if (hospitalId.isEmpty || hospitalPassword.isEmpty) {
      _snack('ID와 비밀번호를 입력해 주세요.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uri = Uri.parse('$_frontUrl/api/auth/login');

      final decoded = await HttpHelper.postJson(uri, {
        'hospital_id': hospitalId,
        'hospital_password': hospitalPassword,
      });

      final ok = decoded['code'] == 1;
      if (!ok) {
        final msg = (decoded['message'] ?? '로그인 실패').toString();
        throw Exception(msg);
      }

      final data = decoded['data'];
      if (data is! Map) throw Exception('로그인 응답 data가 비었습니다.');

      final hospitalCode = int.tryParse(
        data['hospital_code']?.toString() ?? '',
      );
      if (hospitalCode == null) {
        throw Exception('병원 코드(hospital_code)를 읽지 못했습니다.');
      }

      await _storage.write(
        key: _hospitalCodeStorageKey,
        value: hospitalCode.toString(),
      );

      if (!mounted) return;
      context.go('/ward-select');
    } catch (e) {
      debugPrint('[LOGIN] error=$e');
      if (!mounted) return;
      setState(() => _isLoading = false);
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
                      style: TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: _LoginForm(
                      onLogin: _handleLogin,
                      isLoading: _isLoading,
                      hospitalIdController: hospitalIdController,
                      passwordController: passwordController,
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
  final bool isLoading;
  final TextEditingController hospitalIdController;
  final TextEditingController passwordController;

  const _LoginForm({
    required this.onLogin,
    required this.isLoading,
    required this.hospitalIdController,
    required this.passwordController,
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
        const Text(
          'ID',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.hospitalIdController,
          decoration: _deco('아이디를 입력'),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        const Text(
          'Password',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.passwordController,
          obscureText: true,
          decoration: _deco('비밀번호를 입력'),
          onSubmitted: (_) => widget.onLogin(),
        ),
        const SizedBox(height: 18),
        ElevatedButton(
          style: btnStyle,
          onPressed: widget.isLoading ? null : widget.onLogin,
          child: widget.isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('로그인'),
        ),
      ],
    );
  }
}
