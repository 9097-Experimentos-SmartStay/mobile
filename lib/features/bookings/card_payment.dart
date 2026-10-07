import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../domain/staff_models.dart';
import '../../shared/ui.dart';
import '../staff/staff_ui.dart';

/// Card number, holder, expiry and CVV. The payment gateway is simulated: no money moves and the
/// card is never stored (the backend keeps only the brand and last four digits).
class CardFields extends StatelessWidget {
  final TextEditingController number;
  final TextEditingController holder;
  final TextEditingController expiry;
  final TextEditingController cvv;

  const CardFields({super.key, required this.number, required this.holder, required this.expiry, required this.cvv});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: number,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.creditCardNumber],
          decoration: const InputDecoration(labelText: 'Número de tarjeta', prefixIcon: Icon(Icons.credit_card), hintText: '•••• •••• •••• ••••'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: holder,
          textCapitalization: TextCapitalization.characters,
          autofillHints: const [AutofillHints.creditCardName],
          decoration: const InputDecoration(labelText: 'Titular de la tarjeta', prefixIcon: Icon(Icons.person_outline)),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: expiry,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(labelText: 'Vencimiento', hintText: 'MM/AA'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: cvv,
                obscureText: true,
                maxLength: 4,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Código CVV', counterText: ''),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Pays a Pending booking with a card (the amount is always the booking total).
/// Returns true when the payment went through and the booking is now Confirmed.
Future<bool> showCardPaymentSheet(BuildContext context, HotelBooking booking) async {
  final paid = await showStaffSheet<bool>(context, (_) => _CardPaymentForm(booking: booking));
  if (paid == true && context.mounted) {
    showSmartSnack(context, 'Pago aprobado: la reserva ${booking.reference} quedó confirmada.');
  }
  return paid == true;
}

class _CardPaymentForm extends StatefulWidget {
  final HotelBooking booking;

  const _CardPaymentForm({required this.booking});

  @override
  State<_CardPaymentForm> createState() => _CardPaymentFormState();
}

class _CardPaymentFormState extends State<_CardPaymentForm> {
  final _number = TextEditingController();
  final _holder = TextEditingController();
  final _expiry = TextEditingController();
  final _cvv = TextEditingController();
  bool _paying = false;
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    _holder.dispose();
    _expiry.dispose();
    _cvv.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final parsed = CardDetails.parse(number: _number.text, holderName: _holder.text, expiry: _expiry.text, cvv: _cvv.text);
    if (parsed.card == null) return setState(() => _error = parsed.error);

    setState(() {
      _paying = true;
      _error = null;
    });
    try {
      await ApiClient().payWithCard(widget.booking.id, parsed.card!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader('Pagar reserva', subtitle: 'Reserva ${booking.reference}'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18)),
          child: Column(
            children: [
              InfoRow('Estadía', '${formatDay(booking.checkIn)} → ${formatDay(booking.checkOut)}'),
              if (booking.paymentDueAt != null) InfoRow('Pagar antes de', formatDateTime(booking.paymentDueAt)),
              InfoRow('Total', formatMoney(booking.total), strong: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        CardFields(number: _number, holder: _holder, expiry: _expiry, cvv: _cvv),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: kError))),
        const SizedBox(height: 16),
        SmartButton(text: 'Pagar ${formatMoney(booking.total)}', icon: Icons.lock, dark: true, loading: _paying, onPressed: _pay),
        const SizedBox(height: 6),
        const Text('Pago de prueba: no se mueve dinero ni se guarda la tarjeta.',
            textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 12)),
      ],
    );
  }
}
