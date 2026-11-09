import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../i18n/app_strings.dart';
import '../../i18n/i18n.dart';
import '../../state/auth_state.dart';
import '../../state/language_state.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/paige_mascot.dart';

/* The first thing a new person sees: Paige says hi, they pick a language,
   see what the app is, say who is using it, and make an account. Few
   words per page, big buttons, and Skip in the top-right corner (it jumps
   to "who is using it", since an account is still needed).

   "A parent helps me" makes a caregiver account (child profiles and Child
   Mode). "I use it on my own" makes an independent account: a teenager
   with everything in one app. */
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key, this.startAtWho = false, this.onLogin});

  // Opened from the login page's "Create account": skip the hello.
  final bool startAtWho;
  // Shown first thing: "I have an account" goes to the login page.
  final VoidCallback? onLogin;

  static const seenKey = 'welcome_seen';

  static Future<bool> seen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(seenKey) ?? false;
  }

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

enum _Step { hi, language, about, who, account }

class _WelcomePageState extends State<WelcomePage> {
  static const _ink = Color(0xFF26215C);
  static const _cream = Color(0xFFFFF7E8);
  static const _sun = Color(0xFFFFC83D);

  late _Step _step = widget.startAtWho ? _Step.who : _Step.hi;
  bool _independent = false;
  int _age = 13;
  bool _busy = false;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pin = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pin.dispose();
    super.dispose();
  }

  void _go(_Step step) {
    setState(() => _step = step);
    // Seen once they reach "who": next time, open on the login page.
    if (step.index >= _Step.who.index) {
      SharedPreferences.getInstance()
          .then((p) => p.setBool(WelcomePage.seenKey, true));
    }
  }

  // The first page shown: "hi", or "who" when opened from the login page.
  bool get _atStart =>
      _step == _Step.hi || (widget.startAtWho && _step == _Step.who);

  void _back() {
    if (!_atStart) {
      _go(_Step.values[_step.index - 1]);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _toLogin() {
    SharedPreferences.getInstance().then((p) => p.setBool(WelcomePage.seenKey, true));
    final onLogin = widget.onLogin;
    if (onLogin != null) {
      onLogin();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) {
      AppSnackbar.warning(context.trRead('login.err_name_required'), context: context);
      return;
    }
    if (_pin.text.length != 4) {
      AppSnackbar.warning(context.trRead('login.err_pin_4_digits'), context: context);
      return;
    }
    setState(() => _busy = true);
    final auth = context.read<AuthState>();
    final ok = await auth.register(
      name: _name.text.trim(),
      pin: _pin.text,
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      accountType: _independent ? 'independent' : 'caregiver',
      age: _independent ? _age : null,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      AppSnackbar.warning(auth.lastError ?? context.trRead('login.err_auth_failed'),
          context: context);
      return;
    }
    // Signed in: the app opens underneath, so close this if it was pushed.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final showBack = !_atStart || Navigator.of(context).canPop();
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
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
                child: Row(
                  children: [
                    if (showBack)
                      IconButton(
                        iconSize: 32,
                        tooltip: context.tr('common.back'),
                        onPressed: _back,
                        icon: const Icon(Icons.arrow_back_rounded, color: _ink),
                      )
                    else
                      const SizedBox(height: 48),
                    const Spacer(),
                    if (_step.index < _Step.who.index)
                      _Pill(
                        label: context.tr('guide.skip'),
                        icon: Icons.fast_forward_rounded,
                        onTap: () => _go(_Step.who),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0.08, 0), end: Offset.zero)
                          .animate(anim),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(key: ValueKey(_step), child: _body(context)),
                ),
              ),
              if (_step.index < _Step.who.index) ...[
                _Dots(count: 3, index: _step.index),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
                  child: _BigButton(
                    label: context.tr('guide.next'),
                    icon: Icons.arrow_forward_rounded,
                    onTap: () => _go(_Step.values[_step.index + 1]),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    switch (_step) {
      case _Step.hi:
        return _Centered(children: [
          SizedBox(height: width * 0.1),
          PaigeMascot(
            width: math.min(width * 0.6, 260),
            greeting: context.tr('welcome.hi_bubble'),
          ),
          const SizedBox(height: 24),
          _Title(context.tr('welcome.hi_title')),
          const SizedBox(height: 6),
          _Sub(context.tr('welcome.hi_sub')),
        ]);
      case _Step.language:
        final current = context.watch<LanguageState>().code;
        return _Centered(children: [
          const PaigeMascot(width: 150),
          const SizedBox(height: 16),
          _Title(context.tr('welcome.lang_title')),
          const SizedBox(height: 20),
          for (final code in AppStrings.supportedCodes) ...[
            _ChoiceCard(
              emoji: code == 'ms' ? '🇲🇾' : '🇬🇧',
              title: AppStrings.languageNames[code] ?? code,
              selected: current == code,
              onTap: () => context.read<LanguageState>().setLanguage(code),
            ),
            const SizedBox(height: 12),
          ],
        ]);
      case _Step.about:
        return _Centered(children: [
          const PaigeMascot(width: 150),
          const SizedBox(height: 16),
          _Title(context.tr('welcome.about_title')),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _Feature(icon: Icons.auto_stories_rounded, color: const Color(0xFFA9DBB8),
                    label: context.tr('welcome.about_stories')),
              ),
              Expanded(
                child: _Feature(icon: Icons.piano_rounded, color: const Color(0xFFF2B3CB),
                    label: context.tr('welcome.about_music')),
              ),
              Expanded(
                child: _Feature(icon: Icons.diversity_3_rounded, color: const Color(0xFFC9B6EC),
                    label: context.tr('welcome.about_friends')),
              ),
            ],
          ),
        ]);
      case _Step.who:
        return _Centered(children: [
          const PaigeMascot(width: 130),
          const SizedBox(height: 12),
          _Title(context.tr('welcome.who_title')),
          const SizedBox(height: 20),
          _ChoiceCard(
            emoji: '👨‍👩‍👧',
            title: context.tr('welcome.who_parent'),
            subtitle: context.tr('welcome.who_parent_sub'),
            selected: false,
            onTap: () {
              _independent = false;
              _go(_Step.account);
            },
          ),
          const SizedBox(height: 14),
          _ChoiceCard(
            emoji: '🧑',
            title: context.tr('welcome.who_self'),
            subtitle: context.tr('welcome.who_self_sub'),
            selected: false,
            onTap: () {
              _independent = true;
              _go(_Step.account);
            },
          ),
          const SizedBox(height: 20),
          _LoginLink(onTap: _toLogin),
        ]);
      case _Step.account:
        return _Centered(children: [
          const PaigeMascot(width: 110),
          const SizedBox(height: 8),
          _Title(context.tr(_independent ? 'welcome.account_self' : 'welcome.account_parent')),
          const SizedBox(height: 18),
          _Field(controller: _name, hint: context.tr('login.name_hint'), icon: Icons.person_rounded),
          const SizedBox(height: 12),
          _Field(
            controller: _email,
            hint: context.tr('login.email_optional'),
            icon: Icons.mail_rounded,
            keyboard: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          _Field(
            controller: _pin,
            hint: context.tr('login.pin_hint'),
            icon: Icons.lock_rounded,
            keyboard: TextInputType.number,
            obscure: true,
            maxLength: 4,
          ),
          if (_independent) ...[
            const SizedBox(height: 18),
            _Sub(context.tr('welcome.age')),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var a = 10; a <= 18; a++)
                  ChoiceChip(
                    label: Text('$a', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    selected: _age == a,
                    selectedColor: _sun,
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: _ink, width: 2),
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _age = a),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          _BigButton(
            label: context.tr('login.sign_up'),
            icon: Icons.check_rounded,
            busy: _busy,
            onTap: _busy ? null : _create,
          ),
          const SizedBox(height: 10),
          _LoginLink(onTap: _toLogin),
        ]);
    }
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w900,
          color: Color(0xFF26215C),
          height: 1.15,
        ),
      );
}

class _Sub extends StatelessWidget {
  const _Sub(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Color(0xFF3B3570),
        ),
      );
}

// A big tappable choice: an emoji, a short title and maybe one more line.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.emoji,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String emoji;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  static const _ink = Color(0xFF26215C);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? const Color(0xFFFFC83D) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: _ink, width: 3),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 40)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 21, fontWeight: FontWeight.w900, color: _ink)),
                      if (subtitle != null)
                        Text(subtitle!,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF3B3570))),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.arrow_forward_ios_rounded,
                  color: _ink,
                  size: selected ? 32 : 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// One of the three things the app does: a big icon and one word.
class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.color, required this.label});

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF26215C), width: 3),
          ),
          child: Icon(icon, size: 44, color: const Color(0xFF26215C)),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF26215C))),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboard,
    this.obscure = false,
    this.maxLength,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboard;
  final bool obscure;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      obscureText: obscure,
      maxLength: maxLength,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        prefixIcon: Icon(icon, size: 26, color: const Color(0xFF26215C)),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({required this.label, required this.icon, required this.onTap, this.busy = false});

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 62,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFFFC83D),
          foregroundColor: const Color(0xFF26215C),
          disabledBackgroundColor: const Color(0xFFFFE08A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF26215C), width: 3),
          ),
        ),
        onPressed: onTap,
        child: busy
            ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Long labels (or big system text) shrink rather than overflow.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label,
                          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(icon, size: 30),
                ],
              ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const StadiumBorder(side: BorderSide(color: Color(0xFF26215C), width: 2.5)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF26215C))),
              const SizedBox(width: 4),
              Icon(icon, size: 22, color: const Color(0xFF26215C)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginLink extends StatelessWidget {
  const _LoginLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 17),
          children: [
            TextSpan(
              text: context.tr('login.toggle_to_login_prefix'),
              style: const TextStyle(color: Color(0xFF3B3570), fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: context.tr('login.toggle_to_login_action'),
              style: const TextStyle(
                color: Color(0xFF26215C),
                fontWeight: FontWeight.w900,
                decoration: TextDecoration.underline,
                decorationThickness: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 5),
            width: i == index ? 28 : 12,
            height: 12,
            decoration: BoxDecoration(
              color: i == index ? const Color(0xFF26215C) : const Color(0xFF26215C).withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
      ],
    );
  }
}
