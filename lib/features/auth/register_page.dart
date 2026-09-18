import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../shared/ui.dart';

/// Guest passwords must have at least 15 characters (SmartStay API sign-up contract).
const int kGuestPasswordMinLength = 15;

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final ApiClient _api = ApiClient();
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _pendingEmail;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final firstName = _firstName.text.trim();
    final lastName = _lastName.text.trim();
    final email = _email.text.trim();

    if (firstName.length < 2 || lastName.length < 2) {
      showSmartSnack(context, 'Escribe tu nombre y apellido (mínimo 2 caracteres).');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      showSmartSnack(context, 'Escribe un correo válido.');
      return;
    }
    if (_password.text.length < kGuestPasswordMinLength) {
      showSmartSnack(context, 'La contraseña debe tener mínimo $kGuestPasswordMinLength caracteres.');
      return;
    }
    if (_password.text != _confirm.text) {
      showSmartSnack(context, 'Las contraseñas no coinciden.');
      return;
    }

    setState(() => _loading = true);
    try {
      final result = await _api.signUp(
        firstName: firstName,
        lastName: lastName,
        email: email,
        password: _password.text,
      );
      if (!mounted) return;
      setState(() => _pendingEmail = result.email.isEmpty ? email : result.email);
      showSmartSnack(context, result.message);
    } catch (e) {
      if (!mounted) return;
      showSmartSnack(context, 'No se pudo registrar: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    final email = _pendingEmail;
    if (email == null) return;

    setState(() => _loading = true);
    try {
      final message = await _api.resendVerificationEmail(email);
      if (!mounted) return;
      showSmartSnack(context, message);
    } catch (e) {
      if (!mounted) return;
      showSmartSnack(context, 'No se pudo reenviar el correo: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: SmartCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(20),
              child: _pendingEmail == null ? _buildForm(context) : _buildVerifyNotice(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Crear cuenta', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        const Text('Regístrate como cliente para reservar habitaciones.', style: TextStyle(color: kMuted)),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _firstName,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Nombre', prefixIcon: Icon(Icons.person_outline)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _lastName,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Apellido'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.email_outlined)),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _password,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'Contraseña',
            helperText: 'Mínimo $kGuestPasswordMinLength caracteres.',
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _confirm,
          obscureText: _obscure,
          onSubmitted: (_) => _register(),
          decoration: const InputDecoration(labelText: 'Confirmar contraseña', prefixIcon: Icon(Icons.lock)),
        ),
        const SizedBox(height: 24),
        SmartButton(text: 'Registrarme', icon: Icons.person_add, loading: _loading, onPressed: _register),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _loading ? null : () => Navigator.pop(context),
            child: const Text('Ya tengo cuenta'),
          ),
        ),
      ],
    );
  }

  Widget _buildVerifyNotice(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.mark_email_unread_outlined, size: 46, color: kPrimary),
        const SizedBox(height: 14),
        Text('Verifica tu correo', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(
          'Enviamos un enlace de verificación a $_pendingEmail. Ábrelo y luego inicia sesión con ese correo.',
          style: const TextStyle(color: kMuted),
        ),
        const SizedBox(height: 24),
        SmartButton(
          text: 'Ir a iniciar sesión',
          icon: Icons.login,
          onPressed: () => Navigator.pop(context, _pendingEmail),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _loading ? null : _resend,
            child: const Text('Reenviar correo de verificación'),
          ),
        ),
      ],
    );
  }
}
