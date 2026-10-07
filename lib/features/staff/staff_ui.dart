import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../domain/staff_models.dart';
import '../../shared/ui.dart';

const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const monthNames = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];
const weekdayInitials = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
const _weekdays = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

String formatMoney(double amount) => 'S/ ${amount.toStringAsFixed(2)}';

/// "12 oct" (with the year when it is not the current one).
String formatDay(DateTime? date) {
  if (date == null) return '—';
  final base = '${date.day} ${_months[date.month - 1]}';
  return date.year == DateTime.now().year ? base : '$base ${date.year}';
}

/// "lun 12 oct".
String formatWeekday(DateTime date) => '${_weekdays[date.weekday - 1]} ${formatDay(date)}';

String formatDateTime(DateTime? date) {
  if (date == null) return '—';
  return '${formatDay(date)}, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String formatDuration(Duration duration) {
  if (duration.inDays >= 1) return '${duration.inDays} d ${duration.inHours.remainder(24)} h';
  if (duration.inHours >= 1) return '${duration.inHours} h ${duration.inMinutes.remainder(60)} min';
  return '${duration.inMinutes} min';
}

String nightsLabel(int nights) => nights == 1 ? '1 noche' : '$nights noches';

/// The message of an API failure, without the "Exception:" noise.
String errorText(Object error) {
  if (error is ApiException) return error.message;
  return error.toString().replaceFirst('Exception: ', '');
}

({String label, Color color}) bookingStatusStyle(HotelBooking booking) {
  if (booking.isExpired) return (label: 'Vencida', color: kMuted);
  return switch (booking.status) {
    BookingStatus.pending => (label: 'Pendiente de pago', color: const Color(0xFFD97706)),
    BookingStatus.confirmed => (label: 'Confirmada', color: const Color(0xFF16A34A)),
    BookingStatus.checkedIn => (label: 'Hospedado', color: const Color(0xFF2563EB)),
    BookingStatus.cancelled => (label: booking.wasPaid ? 'Cancelada (reembolsada)' : 'Cancelada', color: kError),
    BookingStatus.completed => (label: 'Completada', color: kMuted),
    _ => (label: booking.status, color: kMuted),
  };
}

String roomStatusLabel(String status) => switch (status) {
      RoomStatus.available => 'Disponible',
      RoomStatus.occupied => 'Ocupada',
      RoomStatus.cleaning => 'Limpieza',
      RoomStatus.maintenance => 'Mantenimiento',
      _ => status,
    };

IconData roomStatusIcon(String status) => switch (status) {
      RoomStatus.available => Icons.check_circle_outline,
      RoomStatus.occupied => Icons.person_outline,
      RoomStatus.cleaning => Icons.cleaning_services_outlined,
      RoomStatus.maintenance => Icons.build_outlined,
      _ => Icons.help_outline,
    };

/// Same color code as the web room map: green, red, yellow, dark gray.
({Color background, Color foreground, Color border}) roomStatusColors(String status) => switch (status) {
      RoomStatus.available => (background: const Color(0xFFDCFCE7), foreground: const Color(0xFF14532D), border: const Color(0xFF16A34A)),
      RoomStatus.occupied => (background: const Color(0xFFFEE2E2), foreground: const Color(0xFF7F1D1D), border: const Color(0xFFDC2626)),
      RoomStatus.cleaning => (background: const Color(0xFFFEF9C3), foreground: const Color(0xFF713F12), border: const Color(0xFFEAB308)),
      RoomStatus.maintenance => (background: const Color(0xFF374151), foreground: const Color(0xFFF9FAFB), border: const Color(0xFF111827)),
      _ => (background: kSoftBlue, foreground: kSecondary, border: kLine),
    };

class StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const StatusChip({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withAlpha(28), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }
}

class BookingStatusChip extends StatelessWidget {
  final HotelBooking booking;

  const BookingStatusChip({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    final style = bookingStatusStyle(booking);
    return StatusChip(label: style.label, color: style.color);
  }
}

/// Label/value row used in detail sheets.
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;

  const InfoRow(this.label, this.value, {super.key, this.strong = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: kMuted))),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: strong ? FontWeight.w900 : FontWeight.w600, fontSize: strong ? 16 : 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// Error card with a retry button, for a staff list that failed to load.
class StaffErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const StaffErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.cloud_off_outlined, size: 44, color: kMuted),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: kMuted)),
        const SizedBox(height: 12),
        Center(child: FilledButton.tonalIcon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Reintentar'))),
      ],
    );
  }
}

/// Opens a scrollable bottom sheet that grows with the keyboard.
Future<T?> showStaffSheet<T>(BuildContext context, Widget Function(BuildContext) builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), child: builder(context)),
    ),
  );
}

class SheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const SheetHeader(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 42,
            height: 5,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: kLine, borderRadius: BorderRadius.circular(999)),
          ),
        ),
        Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: const TextStyle(color: kMuted)),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}
