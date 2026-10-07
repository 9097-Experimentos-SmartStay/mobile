import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../domain/models.dart';
import '../../domain/staff_models.dart';
import '../../shared/ui.dart';
import '../auth/login_page.dart';
import '../staff/staff_ui.dart';
import 'card_payment.dart';

class BookingsPage extends StatefulWidget {
  const BookingsPage({super.key});

  @override
  State<BookingsPage> createState() => _BookingsPageState();
}

class _BookingsPageState extends State<BookingsPage> {
  final ApiClient _api = ApiClient();
  late Future<_BookingsData> _future;
  int? _updatingBookingId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_BookingsData> _load() async {
    final results = await Future.wait([_api.getBookings(), _api.getHotels()]);
    return _BookingsData(bookings: results[0] as List<HotelBooking>, hotels: results[1] as List<Hotel>);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  void _openLogin() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  Future<void> _pay(HotelBooking booking) async {
    if (await showCardPaymentSheet(context, booking)) _reload();
  }

  Future<void> _cancelBooking(HotelBooking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Cancelar la reserva ${booking.reference}?'),
        content: Text(
          booking.wasPaid
              ? 'Tu pago quedará como reembolsado y la habitación se liberará.'
              : 'La habitación se liberará para otros huéspedes.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Volver')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kError),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar reserva'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _updatingBookingId = booking.id);
    try {
      await _api.cancelBooking(booking.id);
      if (!mounted) return;
      showSmartSnack(context, 'Reserva cancelada correctamente.');
      _reload();
    } catch (e) {
      if (!mounted) return;
      showSmartSnack(context, 'No se pudo cancelar la reserva: ${errorText(e)}');
    } finally {
      if (mounted) setState(() => _updatingBookingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (SessionStore.currentUser == null) {
      return AuthRequiredCard(
        title: 'Tus reservas aparecerán aquí',
        message: 'Explora hoteles sin cuenta. Cuando quieras reservar o revisar tus reservas, inicia sesión.',
        onLogin: _openLogin,
      );
    }

    return FutureBuilder<_BookingsData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingView(message: 'Cargando tus reservas...');
        }
        if (snapshot.hasError) {
          return EmptyState(
            message: 'No se pudieron cargar tus reservas: ${errorText(snapshot.error!)}',
            buttonText: 'Reintentar',
            onPressed: _reload,
          );
        }

        final data = snapshot.data ?? const _BookingsData(bookings: [], hotels: []);
        if (data.bookings.isEmpty) {
          return EmptyState(
            message: 'Todavía no tienes reservas. Elige un hotel, entra a una habitación y reserva desde ahí.',
            buttonText: 'Actualizar',
            onPressed: _reload,
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 112),
            itemCount: data.bookings.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return const SectionHeader(
                  title: 'Mis reservas',
                  subtitle: 'Revisa el estado de tus habitaciones reservadas.',
                );
              }

              final booking = data.bookings[index - 1];
              return _BookingCard(
                booking: booking,
                hotel: data.hotelFor(booking.hotelId),
                loading: _updatingBookingId == booking.id,
                onPay: () => _pay(booking),
                onCancel: () => _cancelBooking(booking),
              );
            },
          ),
        );
      },
    );
  }
}

class _BookingsData {
  final List<HotelBooking> bookings;
  final List<Hotel> hotels;

  const _BookingsData({required this.bookings, required this.hotels});

  Hotel? hotelFor(int? hotelId) {
    for (final hotel in hotels) {
      if (hotel.id == hotelId) return hotel;
    }
    return null;
  }
}

class _BookingCard extends StatelessWidget {
  final HotelBooking booking;
  final Hotel? hotel;
  final bool loading;
  final VoidCallback onPay;
  final VoidCallback onCancel;

  const _BookingCard({
    required this.booking,
    required this.hotel,
    required this.loading,
    required this.onPay,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final cancelBlock = booking.cancellationBlock;
    return SmartCard(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEEF2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.king_bed_outlined, color: kPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hotel?.name ?? 'Hotel',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('Reserva ${booking.reference} · Hab. ${booking.roomLabel}', style: const TextStyle(color: kMuted)),
                  ],
                ),
              ),
              BookingStatusChip(booking: booking),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.calendar_month_outlined, size: 18, color: kMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text('${formatDay(booking.checkIn)} al ${formatDay(booking.checkOut)} · ${nightsLabel(booking.nights)}'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.person_outline, size: 18, color: kMuted),
              const SizedBox(width: 6),
              Expanded(child: Text(booking.guestName)),
              Text(formatMoney(booking.total), style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          if (booking.isPending && booking.paymentDueAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Págala antes de ${formatDateTime(booking.paymentDueAt)} o se cancelará automáticamente.',
              style: const TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ],
          if (booking.isPending) ...[
            const SizedBox(height: 14),
            SmartButton(text: 'Pagar con tarjeta', icon: Icons.credit_card, dark: true, onPressed: loading ? null : onPay),
          ],
          if (booking.canBeChanged) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: loading || cancelBlock != null ? null : onCancel,
              icon: loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cancel_outlined),
              label: const Text('Cancelar reserva'),
            ),
            if (cancelBlock != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(cancelBlock, style: const TextStyle(color: kMuted, fontSize: 12)),
              ),
          ],
        ],
      ),
    );
  }
}
