import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../domain/staff_models.dart';
import '../../domain/user_role.dart';
import '../../shared/ui.dart';
import 'staff_ui.dart';

enum _BookingAction { pay, change, cancel }

/// Opens a booking: its details and the actions the role may take on it.
/// Returns true when the booking changed (the caller reloads its data).
Future<bool> openStaffBooking(BuildContext context, HotelBooking booking) async {
  final role = SessionStore.currentUser?.role;
  final action = await showStaffSheet<_BookingAction>(context, (context) => _BookingDetail(booking: booking, role: role));
  if (action == null || !context.mounted) return false;
  switch (action) {
    case _BookingAction.pay:
      return showRegisterPaymentSheet(context, booking);
    case _BookingAction.change:
      return showChangeBookingSheet(context, booking);
    case _BookingAction.cancel:
      return confirmCancelBooking(context, booking);
  }
}

class _BookingDetail extends StatelessWidget {
  final HotelBooking booking;
  final String? role;

  const _BookingDetail({required this.booking, required this.role});

  @override
  Widget build(BuildContext context) {
    final canPay = can(role, Capability.registerPayments) && booking.canBePaid;
    final canChange = can(role, Capability.manageBookings) && booking.canBeChanged;
    final canCancel = can(role, Capability.cancelBookings) && booking.canBeChanged;
    final block = booking.cancellationBlock;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader('Reserva ${booking.reference}', subtitle: booking.guestName),
        Align(alignment: Alignment.centerLeft, child: BookingStatusChip(booking: booking)),
        const SizedBox(height: 12),
        InfoRow('Huésped', booking.guestName),
        if (booking.guestEmail.isNotEmpty) InfoRow('Correo', booking.guestEmail),
        if (booking.guestPhone.isNotEmpty) InfoRow('Teléfono', booking.guestPhone),
        InfoRow('Habitación', booking.roomLabel),
        InfoRow('Ingreso', booking.checkIn == null ? '—' : formatWeekday(booking.checkIn!)),
        InfoRow('Salida', booking.checkOut == null ? '—' : formatWeekday(booking.checkOut!)),
        InfoRow('Estadía', nightsLabel(booking.nights)),
        if (booking.isPending && booking.paymentDueAt != null) InfoRow('Pagar antes de', formatDateTime(booking.paymentDueAt)),
        if (booking.confirmedAt != null) InfoRow('Pago registrado', formatDateTime(booking.confirmedAt)),
        if (booking.cancelledAt != null) InfoRow('Cancelada', formatDateTime(booking.cancelledAt)),
        const Divider(height: 24),
        InfoRow('Total', formatMoney(booking.total), strong: true),
        const SizedBox(height: 18),
        if (canPay) ...[
          SmartButton(
            text: 'Registrar pago',
            icon: Icons.account_balance_wallet_outlined,
            dark: true,
            onPressed: () => Navigator.pop(context, _BookingAction.pay),
          ),
          const SizedBox(height: 10),
        ],
        if (canChange)
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, _BookingAction.change),
            icon: const Icon(Icons.edit_calendar_outlined),
            label: const Text('Cambiar fechas o habitación'),
          ),
        if (canCancel) ...[
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: kError),
            onPressed: block == null ? () => Navigator.pop(context, _BookingAction.cancel) : null,
            icon: const Icon(Icons.close),
            label: const Text('Cancelar reserva'),
          ),
          if (block != null) Text(block, textAlign: TextAlign.center, style: const TextStyle(color: kMuted, fontSize: 12)),
        ],
      ],
    );
  }
}

/// Cancellation with the policy: a paid booking gets its payment marked as refunded.
Future<bool> confirmCancelBooking(BuildContext context, HotelBooking booking) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('¿Cancelar la reserva ${booking.reference}?'),
      content: Text(
        booking.wasPaid
            ? 'La reserva ya está pagada: su pago quedará como reembolsado y la habitación se liberará. El huésped recibirá un correo.'
            : 'La habitación se liberará y el huésped recibirá un correo.',
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
  if (confirmed != true || !context.mounted) return false;
  try {
    await ApiClient().cancelBooking(booking.id);
    if (context.mounted) showSmartSnack(context, 'Reserva ${booking.reference} cancelada.');
    return true;
  } catch (e) {
    if (context.mounted) showSmartSnack(context, 'No se pudo cancelar: ${errorText(e)}');
    return false;
  }
}

/// The hotel registers how the guest paid; the amount is always the booking total.
Future<bool> showRegisterPaymentSheet(BuildContext context, HotelBooking booking) async {
  final done = await showStaffSheet<bool>(context, (_) => _RegisterPaymentForm(booking: booking));
  if (done == true && context.mounted) {
    showSmartSnack(context, 'Pago registrado: la reserva ${booking.reference} quedó confirmada.');
  }
  return done == true;
}

class _RegisterPaymentForm extends StatefulWidget {
  final HotelBooking booking;

  const _RegisterPaymentForm({required this.booking});

  @override
  State<_RegisterPaymentForm> createState() => _RegisterPaymentFormState();
}

class _RegisterPaymentFormState extends State<_RegisterPaymentForm> {
  final _operation = TextEditingController();
  final _note = TextEditingController();
  String? _method;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _operation.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final needsOperation = PaymentMethod.requiresOperationNumber(_method);
    final operation = needsOperation ? _operation.text.trim() : '';
    if (_method == null) return setState(() => _error = 'Elige cómo pagó el huésped.');
    if (needsOperation && operation.isEmpty) return setState(() => _error = 'Ingresa el número de operación.');

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient().registerPayment(widget.booking.id, method: _method!, operationNumber: operation, note: _note.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader('Registrar pago', subtitle: 'Reserva ${booking.reference} · ${booking.guestName}'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18)),
          child: Column(
            children: [
              InfoRow('Habitación', '${booking.roomLabel} · ${nightsLabel(booking.nights)}'),
              InfoRow('Monto', formatMoney(booking.total), strong: true),
              const Text('El monto es siempre el total de la reserva.', style: TextStyle(color: kMuted, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text('Método de pago', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final method in PaymentMethod.all)
              ChoiceChip(
                label: Text(PaymentMethod.label(method)),
                selected: _method == method,
                onSelected: _saving ? null : (_) => setState(() => _method = method),
              ),
          ],
        ),
        if (PaymentMethod.requiresOperationNumber(_method)) ...[
          const SizedBox(height: 14),
          TextField(
            controller: _operation,
            maxLength: 50,
            decoration: const InputDecoration(labelText: 'Número de operación *', prefixIcon: Icon(Icons.tag)),
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _note,
          maxLength: 300,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Nota (opcional)', prefixIcon: Icon(Icons.notes)),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: const TextStyle(color: kError))),
        const SizedBox(height: 6),
        SmartButton(text: 'Registrar y confirmar', icon: Icons.check, dark: true, loading: _saving, onPressed: _submit),
      ],
    );
  }
}

/// New dates and/or another room. A paid booking can only move to a stay with the same total.
Future<bool> showChangeBookingSheet(BuildContext context, HotelBooking booking) async {
  final changed = await showStaffSheet<HotelBooking>(context, (_) => _ChangeBookingForm(booking: booking));
  if (changed != null && context.mounted) showSmartSnack(context, 'Reserva ${changed.reference} actualizada.');
  return changed != null;
}

class _ChangeBookingForm extends StatefulWidget {
  final HotelBooking booking;

  const _ChangeBookingForm({required this.booking});

  @override
  State<_ChangeBookingForm> createState() => _ChangeBookingFormState();
}

class _ChangeBookingFormState extends State<_ChangeBookingForm> {
  late DateTimeRange _stay;
  List<AvailableRoom> _rooms = const [];
  int? _roomId; // null keeps the current room
  bool _loadingRooms = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final b = widget.booking;
    _stay = DateTimeRange(start: b.checkIn ?? today, end: b.checkOut ?? addDays(today, 1));
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    setState(() {
      _loadingRooms = true;
      _roomId = null;
    });
    try {
      final rooms = await ApiClient().getAvailableRooms(_stay.start, _stay.end, hotelId: widget.booking.hotelId);
      if (mounted) setState(() => _rooms = rooms.where((r) => r.id != widget.booking.roomId).toList());
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo consultar la disponibilidad: ${errorText(e)}');
    } finally {
      if (mounted) setState(() => _loadingRooms = false);
    }
  }

  Future<void> _pickDates() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: addDays(today, 365 * 2),
      initialDateRange: _stay.start.isBefore(today) ? null : _stay,
      helpText: 'Nuevas fechas de la estadía',
    );
    if (picked == null || picked.duration.inDays < 1) return;
    setState(() => _stay = picked);
    await _loadRooms();
  }

  Future<void> _submit() async {
    final b = widget.booking;
    final datesChanged = _stay.start != b.checkIn || _stay.end != b.checkOut;
    if (!datesChanged && _roomId == null) return setState(() => _error = 'No cambiaste nada.');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final changed = await ApiClient().changeBooking(
        b.id,
        checkIn: datesChanged ? _stay.start : null,
        checkOut: datesChanged ? _stay.end : null,
        roomId: _roomId,
      );
      if (mounted) Navigator.pop(context, changed);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final nights = _stay.duration.inDays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader('Cambiar reserva', subtitle: '${b.reference} · ${b.guestName}'),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.date_range),
          title: Text('${formatDay(_stay.start)} → ${formatDay(_stay.end)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(nightsLabel(nights)),
          trailing: TextButton(onPressed: _saving ? null : _pickDates, child: const Text('Cambiar fechas')),
        ),
        if (b.isConfirmed)
          const Text('La reserva ya está pagada: solo puede cambiar a una estadía con el mismo total.',
              style: TextStyle(color: kMuted, fontSize: 12)),
        const SizedBox(height: 12),
        const Text('Habitación', style: TextStyle(fontWeight: FontWeight.w800)),
        RadioGroup<int?>(
          groupValue: _roomId,
          onChanged: (v) {
            if (!_saving) setState(() => _roomId = v);
          },
          child: Column(
            children: [
              RadioListTile<int?>(
                contentPadding: EdgeInsets.zero,
                value: null,
                title: Text('Mantener la habitación ${b.roomLabel}'),
              ),
              if (_loadingRooms)
                const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
              else
                for (final room in _rooms)
                  RadioListTile<int?>(
                    contentPadding: EdgeInsets.zero,
                    value: room.id,
                    title: Text('${room.label} · ${room.roomTypeName}'),
                    subtitle: Text('${formatMoney(room.pricePerNight)} / noche · total ${formatMoney(room.total)}'),
                  ),
            ],
          ),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_error!, style: const TextStyle(color: kError))),
        const SizedBox(height: 8),
        SmartButton(text: 'Guardar cambios', icon: Icons.check, dark: true, loading: _saving, onPressed: _submit),
      ],
    );
  }
}

/// Desk booking for a phone or walk-in guest without an account. Returns the new booking.
Future<HotelBooking?> showNewBookingSheet(BuildContext context) async {
  final created = await showStaffSheet<HotelBooking>(context, (_) => const _NewBookingForm());
  if (created != null && context.mounted) {
    showSmartSnack(context, 'Reserva ${created.reference} creada. El huésped recibirá un correo con cómo pagar.');
  }
  return created;
}

class _NewBookingForm extends StatefulWidget {
  const _NewBookingForm();

  @override
  State<_NewBookingForm> createState() => _NewBookingFormState();
}

class _NewBookingFormState extends State<_NewBookingForm> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  DateTimeRange _stay = DateTimeRange(start: today, end: addDays(today, 1));
  List<AvailableRoom>? _rooms;
  AvailableRoom? _room;
  bool _loadingRooms = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _loadRooms() async {
    setState(() {
      _loadingRooms = true;
      _room = null;
      _error = null;
    });
    try {
      final rooms = await ApiClient().getAvailableRooms(_stay.start, _stay.end, hotelId: SessionStore.currentUser?.hotelId);
      if (mounted) setState(() => _rooms = rooms);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo consultar la disponibilidad: ${errorText(e)}');
    } finally {
      if (mounted) setState(() => _loadingRooms = false);
    }
  }

  Future<void> _pickDates() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: addDays(today, 365 * 2),
      initialDateRange: _stay,
      helpText: 'Fechas de la estadía',
    );
    if (picked == null || picked.duration.inDays < 1) return;
    setState(() => _stay = picked);
    await _loadRooms();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    String? error;
    if (_room == null) {
      error = 'Elige una habitación.';
    } else if (name.length < 2) {
      error = 'Ingresa el nombre del huésped.';
    } else if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      error = 'Ingresa un correo válido: ahí le llegará la reserva.';
    } else if (phone.isNotEmpty && !RegExp(r'^\+?\d{7,15}$').hasMatch(phone.replaceAll(' ', ''))) {
      error = 'El teléfono debe tener entre 7 y 15 dígitos.';
    }
    if (error != null) return setState(() => _error = error);

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final booking = await ApiClient().createDeskBooking(
        roomId: _room!.id,
        checkIn: _stay.start,
        checkOut: _stay.end,
        guestName: name,
        guestEmail: email,
        guestPhone: phone.replaceAll(' ', ''),
      );
      if (mounted) Navigator.pop(context, booking);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _rooms;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeader('Nueva reserva', subtitle: 'Para un huésped que llama o llega a recepción.'),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.date_range),
          title: Text('${formatDay(_stay.start)} → ${formatDay(_stay.end)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(nightsLabel(_stay.duration.inDays)),
          trailing: TextButton(onPressed: _saving ? null : _pickDates, child: const Text('Cambiar')),
        ),
        const Text('Habitación disponible', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        if (_loadingRooms)
          const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
        else if (rooms != null && rooms.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No hay habitaciones libres para esas fechas.', style: TextStyle(color: kMuted)),
          )
        else if (rooms != null)
          RadioGroup<int>(
            groupValue: _room?.id,
            onChanged: (id) {
              if (!_saving) setState(() => _room = rooms.firstWhere((room) => room.id == id));
            },
            child: Column(
              children: [
                for (final room in rooms)
                  RadioListTile<int>(
                    contentPadding: EdgeInsets.zero,
                    value: room.id,
                    title: Text('${room.label} · ${room.roomTypeName}'),
                    subtitle: Text('${formatMoney(room.pricePerNight)} / noche · total ${formatMoney(room.total)}'),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nombre del huésped *', prefixIcon: Icon(Icons.person_outline)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Correo *', prefixIcon: Icon(Icons.mail_outline)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Teléfono (opcional)', prefixIcon: Icon(Icons.phone_outlined)),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: kError))),
        const SizedBox(height: 16),
        SmartButton(text: 'Crear reserva', icon: Icons.check, dark: true, loading: _saving, onPressed: _submit),
        const SizedBox(height: 6),
        const Text(
          'Queda pendiente de pago por 24 horas. Registra el pago cuando el huésped pague.',
          textAlign: TextAlign.center,
          style: TextStyle(color: kMuted, fontSize: 12),
        ),
      ],
    );
  }
}
