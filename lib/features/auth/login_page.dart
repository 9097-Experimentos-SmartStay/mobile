import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../client/client_shell.dart';
import '../../shared/ui.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final ApiClient _api = ApiClient();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _email.text.trim();
    if (!email.contains('@') || _password.text.isEmpty) {
      showSmartSnack(context, 'Ingresa tu correo y contraseña.');
      return;
    }

    setState(() => _loading = true);
    try {
      await _api.signIn(email, _password.text);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ClientShell()));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.emailNotVerified) {
        _offerResend(email, e.message);
      } else {
        showSmartSnack(context, e.message);
      }
    } catch (e) {
      if (!mounted) return;
      showSmartSnack(context, 'No se pudo iniciar sesión: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _offerResend(String email, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Reenviar',
          onPressed: () async {
            try {
              final result = await _api.resendVerificationEmail(email);
              if (!mounted) return;
              showSmartSnack(context, result);
            } catch (e) {
              if (!mounted) return;
              showSmartSnack(context, 'No se pudo reenviar el correo: $e');
            }
          },
        ),
      ),
    );
  }

  Future<void> _openRegister() async {
    final email = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const RegisterPage()),
    );
    if (email != null && mounted) _email.text = email;
  }

  @override
  Widget build(BuildContext context) {
    final canClose = Navigator.canPop(context);
    return Scaffold(
      backgroundColor: kSurface,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [kSoftBlue, Colors.white, kSurface],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: canClose
                            ? IconButton.filledTonal(
                                tooltip: 'Cerrar',
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close),
                              )
                            : const SizedBox(height: 48),
                      ),
                      const SizedBox(height: 22),
                      Container(
                        height: 188,
                        width: double.infinity,
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: kSecondary,
                          borderRadius: BorderRadius.circular(34),
                          boxShadow: [BoxShadow(color: Colors.black.withAlpha(22), blurRadius: 28, offset: const Offset(0, 14))],
                          image: const DecorationImage(
                            image: NetworkImage('https://images.unsplash.com/photo-1505693416388-ac5ce068fe85?auto=format&fit=crop&w=1000&q=80'),
                            fit: BoxFit.cover,
                            opacity: 0.58,
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SmartLogoMark(size: 58, framed: true),
                              const SizedBox(height: 10),
                              const Text('Tu próxima estadía, más cerca.', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [BoxShadow(color: Colors.black.withAlpha(12), blurRadius: 24, offset: const Offset(0, 12))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Bienvenido de nuevo', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 6),
                            const Text('Inicia sesión solo cuando quieras reservar o ver tus datos.', style: TextStyle(color: kMuted)),
                            const SizedBox(height: 22),
                            TextField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.mail_outline)),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _password,
                              obscureText: _obscure,
                              decoration: InputDecoration(
                                labelText: 'Contraseña',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                ),
                              ),
                              onSubmitted: (_) => _login(),
                            ),
                            const SizedBox(height: 20),
                            SmartButton(text: 'Iniciar sesión', icon: Icons.login, loading: _loading, dark: true, onPressed: _login),
                            const SizedBox(height: 12),
                            Center(
                              child: TextButton(
                                onPressed: _loading ? null : _openRegister,
                                child: const Text('Crear una cuenta nueva'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextButton(
                        onPressed: () => Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const ClientShell()),
                          (_) => false,
                        ),
                        child: const Text('Seguir explorando sin iniciar sesión'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
