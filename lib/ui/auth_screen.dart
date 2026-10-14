import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/friendly_error.dart';
import '../state/providers.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  int _mode = 0; // 0: sign in, 1: join team
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    for (final c in [_name, _code, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    final auth = ref.read(authProvider.notifier);
    String? msg;
    if (_mode == 0) {
      msg = await auth.signIn(_email.text.trim(), _password.text);
    } else if (_mode == 1) {
      final org = await auth.orgNameForCode(_code.text);
      msg = org == null
          ? 'That join code was not found. Ask your manager or owner for the code.'
          : await auth.signUp(
              email: _email.text.trim(),
              password: _password.text,
              fullName: _name.text.trim(),
              joinCode: _code.text.trim(),
            );
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (msg != null) {
      FriendlyError.show(context, msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Elegant modern header with App Logo
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(28, MediaQuery.paddingOf(context).top + 32, 28, 36),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          const Color(0xFF0F2027),
                          const Color(0xFF203A43),
                          const Color(0xFF2C5364),
                        ]
                      : [
                          cs.primary,
                          cs.primaryContainer,
                        ],
                ),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Official Mela verified logo badge
                      Container(
                        width: 58,
                        height: 58,
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: isDark ? 0.2 : 0.6),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified_rounded, size: 14, color: isDark ? Colors.white : cs.onPrimary),
                            const SizedBox(width: 5),
                            Text(
                              'VERIFIED LEDGER',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: isDark ? Colors.white : cs.onPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Mela',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: isDark ? Colors.white : cs.onPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Scan transfers. Skip fake screenshots.\nClose every shift with complete confidence.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white.withValues(alpha: 0.85) : cs.onPrimary.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),

            // Form container
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Segmented Button
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      segments: const [
                        ButtonSegment(
                          value: 0,
                          icon: Icon(Icons.login_rounded, size: 18),
                          label: Text('Sign In', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        ButtonSegment(
                          value: 1,
                          icon: Icon(Icons.group_add_rounded, size: 18),
                          label: Text('Join Team', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (s) => setState(() => _mode = s.first),
                    ),
                    const SizedBox(height: 22),

                    if (_mode == 1) ...[
                      _buildTextField(
                        controller: _name,
                        label: 'Full Name',
                        hint: 'e.g. Abebe Kebede',
                        icon: Icons.person_outline_rounded,
                        validator: _required,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: _code,
                        label: 'Team Join Code',
                        hint: 'e.g. 6-character code from owner',
                        icon: Icons.vpn_key_rounded,
                        caps: true,
                        letterSpacing: 2.0,
                        validator: _required,
                      ),
                      const SizedBox(height: 14),
                    ],

                    _buildTextField(
                      controller: _email,
                      label: 'Email Address',
                      hint: 'name@business.com',
                      icon: Icons.alternate_email_rounded,
                      type: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || !v.contains('@')) return 'Please enter a valid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Password / Temporary PIN',
                        hintText: '••••••••',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters required' : null,
                    ),
                    const SizedBox(height: 26),

                    // Primary Submit Button
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _loading ? null : _submit,
                      icon: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : Icon(_mode == 0 ? Icons.arrow_forward_rounded : Icons.check_circle_rounded),
                      label: Text(
                        _loading ? 'Verifying…' : (_mode == 0 ? 'Sign In to Mela' : 'Join Team & Start Shift'),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Professional footer note
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shield_outlined, size: 16, color: cs.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(
                          'Telebirr · CBE · CBE Birr · Dashen · Awash',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        'Offline resilient · Instant bank verification',
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.8)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? type,
    String? Function(String?)? validator,
    bool caps = false,
    double? letterSpacing,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: type,
      textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.words,
      style: letterSpacing != null ? TextStyle(letterSpacing: letterSpacing, fontWeight: FontWeight.w700) : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
      ),
      validator: validator,
    );
  }
}
