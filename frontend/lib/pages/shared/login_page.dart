import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/soft_card.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isRegisterMode = false;
  bool _busy = false;
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_pinCtrl.text.length != 4) {
      _toast(context.trRead('login.err_pin_4_digits'));
      return;
    }
    if (_isRegisterMode && _nameCtrl.text.trim().isEmpty) {
      _toast(context.trRead('login.err_name_required'));
      return;
    }
    setState(() => _busy = true);
    final auth = context.read<AuthState>();
    final ok = _isRegisterMode
        ? await auth.register(
            name: _nameCtrl.text.trim(),
            pin: _pinCtrl.text,
            email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
          )
        : await auth.login(
            pin: _pinCtrl.text,
            email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
          );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) _toast(auth.lastError ?? context.trRead('login.err_auth_failed'));
  }

  void _toast(String msg) {
    AppSnackbar.warning(msg, context: context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: SoftCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 68, height: 68,
                    decoration: const BoxDecoration(
                      color: AppColors.iconCircleBlue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.menu_book_outlined, size: 32),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isRegisterMode
                        ? context.tr('login.create_account')
                        : context.tr('login.welcome_back'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isRegisterMode
                        ? context.tr('login.subtitle_register')
                        : context.tr('login.subtitle_login'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 22),
                  if (_isRegisterMode) ...[
                    TextField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                          hintText: context.tr('login.name_hint')),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: _isRegisterMode
                          ? context.tr('login.email_optional')
                          : context.tr('login.email'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pinCtrl,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    decoration: InputDecoration(
                      hintText: context.tr('login.pin_hint'),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: AppColors.textPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _isRegisterMode
                                  ? context.tr('login.sign_up')
                                  : context.tr('login.sign_in'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _isRegisterMode = !_isRegisterMode),
                    // The question stays grey; the action verb is coloured +
                    // underlined so it clearly looks tappable.
                    child: Text.rich(
                      TextSpan(
                        style: const TextStyle(fontSize: 14),
                        children: [
                          TextSpan(
                            text: _isRegisterMode
                                ? context.tr('login.toggle_to_login_prefix')
                                : context.tr('login.toggle_to_register_prefix'),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          TextSpan(
                            text: _isRegisterMode
                                ? context.tr('login.toggle_to_login_action')
                                : context.tr('login.toggle_to_register_action'),
                            style: const TextStyle(
                              color: AppColors.primaryBlueDark,
                              fontWeight: FontWeight.w800,
                              decoration: TextDecoration.underline,
                              decorationThickness: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
