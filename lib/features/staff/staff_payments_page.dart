import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../domain/staff_models.dart';
import '../../shared/ui.dart';
import 'staff_ui.dart';

/// Payments of the hotel: amount, method, operation number and status (Refunded when the booking
/// was cancelled after paying). The API has no "list payments" endpoint: like the web app, the
/// payment of each booking that was ever paid is requested.
class StaffPaymentsPage extends StatefulWidget {
  const StaffPaymentsPage({super.key});

  @override
  State<StaffPaymentsPage> createState() => _StaffPaymentsPageState();
}

class _PaymentRow {
  final StaffPayment payment;
  final HotelBooking booking;

  const _PaymentRow(this.payment, this.booking);
}

class _StaffPaymentsPageState extends State<StaffPaymentsPage> {
  List<_PaymentRow> _rows = const [];
  bool _loading = true;
  bool _partial = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _partial = false;
    });
    try {
      final api = ApiClient();
      final paid = (await api.getBookings()).where((b) => b.wasPaid).toList();
      var failures = 0;
      final rows = await Future.wait(paid.map((booking) async {
        try {
          return _PaymentRow(await api.getPaymentOfBooking(booking.id), booking);
        } catch (_) {
          failures += 1;
          return null;
        }
      }));
      final list = rows.whereType<_PaymentRow>().toList()
        ..sort((a, b) => (b.payment.paymentDate ?? DateTime(0)).compareTo(a.payment.paymentDate ?? DateTime(0)));
      if (mounted) {
        setState(() {
          _rows = list;
          _partial = failures > 0;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudieron cargar los pagos: ${errorText(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _rows.where((r) => !r.payment.isRefunded).fold<double>(0, (sum, r) => sum + r.payment.amount);
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        title: const Text('Pagos', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [IconButton(tooltip: 'Actualizar', onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading && _rows.isEmpty
          ? const LoadingView(message: 'Cargando pagos...')
          : _error != null && _rows.isEmpty
              ? StaffErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                    children: [
                      if (_partial)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text('Algunos pagos no se pudieron cargar.', style: TextStyle(color: Color(0xFFD97706))),
                        ),
                      if (_rows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('Aún no hay pagos registrados.', textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
                        )
                      else ...[
                        SmartCard(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.account_balance_wallet_outlined, color: kPrimaryDark),
                              const SizedBox(width: 12),
                              Expanded(child: Text('${_rows.length} pagos', style: const TextStyle(fontWeight: FontWeight.w700))),
                              Text(formatMoney(total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                            ],
                          ),
                        ),
                        for (final row in _rows) _PaymentCard(row: row),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final _PaymentRow row;

  const _PaymentCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final payment = row.payment;
    final booking = row.booking;
    return SmartCard(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(booking.reference, style: const TextStyle(fontWeight: FontWeight.w900)),
              const Spacer(),
              StatusChip(
                label: payment.isRefunded ? 'Reembolsado' : 'Completado',
                color: payment.isRefunded ? kMuted : const Color(0xFF16A34A),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(booking.guestName, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            [
              PaymentMethod.label(payment.method),
              if (payment.operationNumber.isNotEmpty) 'Op. ${payment.operationNumber}',
              formatDateTime(payment.paymentDate),
            ].join(' · '),
            style: const TextStyle(color: kMuted, fontSize: 13),
          ),
          if (payment.refundedAt != null)
            Text('Reembolsado ${formatDateTime(payment.refundedAt)}', style: const TextStyle(color: kMuted, fontSize: 12)),
          if (payment.note.isNotEmpty) Text(payment.note, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              formatMoney(payment.amount),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                decoration: payment.isRefunded ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
