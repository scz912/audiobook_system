import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../state/auth_state.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/paige_mascot.dart';
import '../onboarding/welcome_page.dart';
import '../../widgets/whole_words_text.dart';

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

  // The welcome flow's look, so signing in and signing up feel like one app.
  static const _ink = Color(0xFF26215C);
  static const _inkSoft = Color(0xFF3B3570);
  static const _cream = Color(0xFFFFF7E8);
  static const _sun = Color(0xFFFFC83D);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.35),
            radius: 1.0,
            colors: [Color(0xFFFFE9A8), _cream],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: _ink, width: 3),
                    boxShadow: [
                      BoxShadow(color: _ink.withValues(alpha: 0.18), offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Center(child: PaigeMascot(width: 120)),
                      const SizedBox(height: 12),
                      WholeWordsText(
                        context.tr('login.welcome_back'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: _ink,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.tr('login.subtitle_login'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 17, color: _inkSoft, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 22),
                      TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        decoration: InputDecoration(
                          hintText: context.tr('login.email'),
                          prefixIcon: const Icon(Icons.mail_rounded, size: 26, color: _ink),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pinCtrl,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        maxLength: 4,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        decoration: InputDecoration(
                          hintText: context.tr('login.pin_hint'),
                          counterText: '',
                          prefixIcon: const Icon(Icons.lock_rounded, size: 26, color: _ink),
                        ),
                        onSubmitted: (_) => _busy ? null : _submit(),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 62,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _sun,
                            foregroundColor: _ink,
                            disabledBackgroundColor: const Color(0xFFFFE08A),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: const BorderSide(color: _ink, width: 3),
                            ),
                          ),
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: 26,
                                  height: 26,
                                  child: CircularProgressIndicator(strokeWidth: 3, color: _ink),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          context.tr('login.sign_in'),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w900, fontSize: 21),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.arrow_forward_rounded, size: 30),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: _busy ? null : _createAccount,
                        // The question stays soft; the action is bold and
                        // underlined so it clearly looks tappable.
                        child: Text.rich(
                          textAlign: TextAlign.center,
                          TextSpan(
                            style: const TextStyle(fontSize: 17),
                            children: [
                              TextSpan(
                                text: context.tr('login.toggle_to_register_prefix'),
                                style: const TextStyle(
                                  color: _inkSoft,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(
                                text: context.tr('login.toggle_to_register_action'),
                                style: const TextStyle(
                                  color: _ink,
                                  fontWeight: FontWeight.w900,
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
        ),
      ),
    );
  }
}
