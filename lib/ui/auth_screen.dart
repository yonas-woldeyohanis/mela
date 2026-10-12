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
  final _org = TextEditingController();
  final _code = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  int _mode = 0; // 0 sign in, 1 create business, 2 join team
  bool _loading = false, _obscure = true;

  @override
  void dispose() {
    for (final c in [_name, _org, _code, _email, _password]) {
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
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(28, MediaQuery.paddingOf(context).top + 36, 28, 36),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [cs.primary, cs.tertiary]),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(18)),
                child: Icon(Icons.receipt_long_rounded, color: cs.onPrimary, size: 32),
              ),
              const SizedBox(height: 20),
              Text('Mela', style: tt.headlineLarge?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Scan transfers. Skip the screenshots.\nClose every shift with confidence.',
                  style: tt.bodyLarge?.copyWith(color: cs.onPrimary.withValues(alpha: 0.9))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Sign in')),
                    ButtonSegment(value: 1, label: Text('Join staff team')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
                const SizedBox(height: 20),
                if (_mode == 1) ...[
                  _field(_name, 'Full name', Icons.person_outline, validator: _required),
                  const SizedBox(height: 12),
                  _field(_code, 'Team join code', Icons.vpn_key_outlined, validator: _required, caps: true),
                  const SizedBox(height: 12),
                ],
                  _field(_email, 'Email address', Icons.alternate_email, type: TextInputType.emailAddress, validator: (v) {
                    if (v == null || !v.contains('@')) return 'Enter a valid email';
                    return null;
                  }),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Password / Temporary PIN',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Text(_mode == 0 ? 'Sign in' : 'Join team'),
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  Widget _field(TextEditingController c, String label, IconData icon,
      {TextInputType? type, String? Function(String?)? validator, bool caps = false}) {
    return TextFormField(
      controller: c,
      keyboardType: type,
      textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.words,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      validator: validator,
    );
  }
}
