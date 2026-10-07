import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api_client.dart';
import '../../domain/models.dart';
import '../../shared/ui.dart';
import '../client/client_shell.dart';
import '../staff/staff_shell.dart';

/// Second step of the sign-in for staff accounts (US-52): enrolls an authenticator
/// app the first time, then asks for its 6-digit code (or a recovery code).
class MfaPage extends StatefulWidget {
  final MfaChallenge challenge;

  const MfaPage({super.key, required this.challenge});

  @override
  State<MfaPage> createState() => _MfaPageState();
}

class _MfaPageState extends State<MfaPage> {
  final ApiClient _api = ApiClient();
  final TextEditingController _code = TextEditingController();
  MfaEnrollment? _enrollment;
  bool _useRecoveryCode = false;
  bool _loading = false;
  String? _enrollmentError;

  bool get _enrolling => widget.challenge.enrollmentRequired;

  @override
  void initState() {
    super.initState();
    if (_enrolling) _startEnrollment();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _startEnrollment() async {
    setState(() {
      _loading = true;
      _enrollmentError = null;
    });
    try {
      final enrollment = await _api.startMfaEnrollment(widget.challenge.mfaToken);
      if (!mounted) return;
      setState(() => _enrollment = enrollment);
    } catch (e) {
      if (!mounted) return;
      setState(() => _enrollmentError = 'No se pudo preparar la verificación en dos pasos: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final value = _code.text.trim();
    if (_useRecoveryCode ? value.isEmpty : !RegExp(r'^\d{3}\s?\d{3}$').hasMatch(value)) {
      showSmartSnack(context, _useRecoveryCode ? 'Ingresa un código de recuperación.' : 'Ingresa el código de 6 dígitos.');
      return;
    }

    setState(() => _loading = true);
    try {
      final token = widget.challenge.mfaToken;
      if (_enrolling) {
        final recoveryCodes = await _api.confirmMfaEnrollment(token, value);
        if (!mounted) return;
        if (recoveryCodes.isNotEmpty) await _showRecoveryCodes(recoveryCodes);
      } else if (_useRecoveryCode) {
        await _api.verifyMfa(token, recoveryCode: value);
      } else {
        await _api.verifyMfa(token, code: value);
      }
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => homeFor(const ClientShell())), (_) => false);
    } on ApiException catch (e) {
      if (!mounted) return;
      showSmartSnack(context, e.message);
    } catch (e) {
      if (!mounted) return;
      showSmartSnack(context, 'No se pudo verificar el código: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showRecoveryCodes(List<String> codes) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Guarda tus códigos de recuperación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cada uno sirve una sola vez si no tienes el teléfono a mano. No se volverán a mostrar.'),
            const SizedBox(height: 14),
            SelectableText(codes.join('\n'), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: codes.join('\n')));
              showSmartSnack(context, 'Códigos copiados.');
            },
            child: const Text('Copiar'),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Ya los guardé')),
        ],
      ),
    );
  }

  Widget _enrollmentSteps() {
    final enrollment = _enrollment;
    if (_enrollmentError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_enrollmentError!, style: const TextStyle(color: Colors.redAccent)),
          const SizedBox(height: 10),
          TextButton.icon(onPressed: _loading ? null : _startEnrollment, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
        ],
      );
    }
    if (enrollment == null) {
      return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '1. Abre Google Authenticator, Microsoft Authenticator u otra app similar y agrega una cuenta con la clave de configuración:',
          style: TextStyle(color: kMuted),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
          decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  enrollment.secret,
                  style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, letterSpacing: 1.2),
                ),
              ),
              IconButton(
                tooltip: 'Copiar clave',
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: enrollment.secret));
                  showSmartSnack(context, 'Clave copiada.');
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text('Cuenta: ${enrollment.accountName} · Tipo: basada en tiempo', style: const TextStyle(color: kMuted, fontSize: 12)),
        const SizedBox(height: 14),
        const Text('2. Escribe el código de 6 dígitos que muestra la app.', style: TextStyle(color: kMuted)),
        const SizedBox(height: 14),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = !_enrolling || _enrollment != null;
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(backgroundColor: kSurface, title: const Text('Verificación en dos pasos')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Container(
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
                    Text(
                      _enrolling ? 'Configura tu autenticador' : 'Ingresa tu código',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _enrolling
                          ? 'Las cuentas del personal del hotel requieren verificación en dos pasos.'
                          : 'Abre tu app de autenticación para ${widget.challenge.email}.',
                      style: const TextStyle(color: kMuted),
                    ),
                    const SizedBox(height: 18),
                    if (_enrolling) _enrollmentSteps(),
                    if (ready) ...[
                      TextField(
                        controller: _code,
                        autofocus: !_enrolling,
                        keyboardType: _useRecoveryCode ? TextInputType.text : TextInputType.number,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: _useRecoveryCode ? 40 : 7,
                        decoration: InputDecoration(
                          labelText: _useRecoveryCode ? 'Código de recuperación' : 'Código de 6 dígitos',
                          prefixIcon: Icon(_useRecoveryCode ? Icons.key_outlined : Icons.pin_outlined),
                          counterText: '',
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 20),
                      SmartButton(text: 'Verificar', icon: Icons.verified_user_outlined, loading: _loading, dark: true, onPressed: _submit),
                      if (!_enrolling)
                        Center(
                          child: TextButton(
                            onPressed: _loading
                                ? null
                                : () => setState(() {
                                      _useRecoveryCode = !_useRecoveryCode;
                                      _code.clear();
                                    }),
                            child: Text(_useRecoveryCode ? 'Usar el código de la app' : 'No tengo mi teléfono: usar código de recuperación'),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
