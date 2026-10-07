import 'package:flutter/material.dart';
import '../analytics_service.dart';
import '../services/admin_auth_service.dart';
import '../widgets/theme_mode_button.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.auth, this.accessMessage});

  final AdminAuthService? auth;
  final String? accessMessage;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final AdminAuthService _auth;
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;
  bool hidePassword = true;

  @override
  void initState() {
    super.initState();
    _auth = widget.auth ?? SupabaseAdminAuthService();
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (loading) return;
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your admin email and password.')),
      );
      return;
    }

    setState(() => loading = true);
    await AnalyticsService.capture('admin login attempted');
    try {
      await _auth.signInWithPassword(
        email: email.text.trim(),
        password: password.text,
      );
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString().toLowerCase();
      final networkProblem = raw.contains('socketexception') ||
          raw.contains('network is unreachable') ||
          raw.contains('connection failed') ||
          raw.contains('failed host lookup') ||
          raw.contains('timed out') ||
          raw.contains('clientexception');
      await AnalyticsService.capture(
        'admin login failed',
        properties: {
          'reason': networkProblem ? 'network' : 'credentials',
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            networkProblem
                ? 'Can’t reach the sign-in service. Check your connection and try again.'
                : 'Login failed. Check your email and password.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 8,
              right: 8,
              child: const ThemeModeButton(),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                      side: BorderSide(
                        color: colors.outlineVariant.withValues(alpha: .55),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  colors.primary,
                                  colors.primaryContainer,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.sports_soccer_rounded,
                              size: 42,
                              color: colors.onPrimary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Football Admin',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Manage live matches, stream links and highlights.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              height: 1.4,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 28),
                          if (widget.accessMessage != null) ...[
                            Text(
                              widget.accessMessage!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.error),
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextField(
                            controller: email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Admin email',
                              prefixIcon: Icon(Icons.alternate_email_rounded),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: password,
                            obscureText: hidePassword,
                            onSubmitted: (_) => loading ? null : login(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                  () => hidePassword = !hidePassword,
                                ),
                                icon: Icon(
                                  hidePassword
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: loading ? null : login,
                              icon: loading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.login_rounded),
                              label: Text(
                                loading ? 'SIGNING IN...' : 'SIGN IN',
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.verified_user_outlined,
                                size: 16,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Admin access only',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
