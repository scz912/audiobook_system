import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/paige_mascot.dart';
import '../../widgets/soft_card.dart';
import '../onboarding/welcome_page.dart';

/* Sign in with email and PIN. New accounts are made in the welcome flow
   ("Create account" opens it at "who is using the app"), which asks
   whether a parent helps or the person uses the app on their own. */
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _busy = false;
  final _emailCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_pinCtrl.text.length != 4) {
      _toast(context.trRead('login.err_pin_4_digits'));
      return;
    }
    setState(() => _busy = true);
    final auth = context.read<AuthState>();
    final ok = await auth.login(
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

  void _createAccount() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WelcomePage(startAtWho: true)),
    );
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
                  const Center(child: PaigeMascot(width: 120)),
                  const SizedBox(height: 12),
                  Text(
                    context.tr('login.welcome_back'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr('login.subtitle_login'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: context.tr('login.email'),
                      prefixIcon: const Icon(Icons.mail_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pinCtrl,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: context.tr('login.pin_hint'),
                      counterText: '',
                      prefixIcon: const Icon(Icons.lock_rounded),
                    ),
                    onSubmitted: (_) => _busy ? null : _submit(),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: AppColors.textPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              context.tr('login.sign_in'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 18),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _busy ? null : _createAccount,
                    // The question stays grey; the action verb is coloured +
                    // underlined so it clearly looks tappable.
                    child: Text.rich(
                      TextSpan(
                        style: const TextStyle(fontSize: 16),
                        children: [
                          TextSpan(
                            text: context.tr('login.toggle_to_register_prefix'),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextSpan(
                            text: context.tr('login.toggle_to_register_action'),
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
