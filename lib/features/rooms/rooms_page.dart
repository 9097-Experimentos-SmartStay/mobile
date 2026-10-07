import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../domain/models.dart';
import '../../domain/staff_models.dart';
import '../../shared/ui.dart';
import '../auth/login_page.dart';
import '../bookings/card_payment.dart';
import '../staff/staff_ui.dart' show errorText;

class RoomsPage extends StatefulWidget {
  final Hotel? selectedHotel;
  final ValueChanged<HotelBooking>? onBookingCreated;
  final VoidCallback? onShowHotels;

  const RoomsPage({
    super.key,
    this.selectedHotel,
    this.onBookingCreated,
    this.onShowHotels,
  });

  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends State<RoomsPage> {
  final ApiClient _api = ApiClient();
  late Future<_RoomsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant RoomsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedHotel?.id != widget.selectedHotel?.id) {
      _reload();
    }
  }

  Future<_RoomsData> _load() async {
    final hotels = await _api.getHotels();
    final rooms = widget.selectedHotel == null ? await _api.getRooms() : await _api.getRoomsByHotel(widget.selectedHotel!.id);
    return _RoomsData(hotels: hotels, rooms: rooms);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _openBookingSheet(Room room, Hotel? hotel) async {
    if (SessionStore.currentUser == null) {
      _showLoginRequired();
      return;
    }

    final outcome = await showModalBottomSheet<_BookingOutcome>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BookingSheet(api: _api, room: room, hotel: hotel),
    );

    if (outcome == null || !mounted) return;
    final code = outcome.booking.reference;
    if (outcome.paymentError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text('Reserva $code creada, pero el pago no se completó: ${outcome.paymentError} '
            'Puedes pagarla desde Reservas antes de que venza.'),
      ));
    } else {
      showSmartSnack(
        context,
        outcome.paid
            ? 'Pago aprobado: la reserva $code quedó confirmada.'
            : 'Reserva $code creada. Págala antes de 24 horas o se cancelará.',
      );
    }
    widget.onBookingCreated?.call(outcome.booking);
  }

  void _showLoginRequired() {
    showAuthPromptSheet(
      context,
      title: 'Inicia sesión para reservar',
      message: 'Ingresa a tu cuenta para continuar con la reserva.',
      onLogin: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_RoomsData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingView(message: 'Cargando habitaciones disponibles...');
        }
        if (snapshot.hasError) {
          return EmptyState(message: snapshot.error.toString(), buttonText: 'Reintentar', onPressed: _reload);
        }

        final data = snapshot.data ?? const _RoomsData(hotels: [], rooms: []);
        if (data.rooms.isEmpty) {
          return EmptyState(
            message: widget.selectedHotel == null
                ? 'No hay habitaciones disponibles'
                : 'Este hotel todavía no tiene habitaciones disponibles',
            buttonText: widget.selectedHotel == null ? 'Actualizar' : 'Volver a hoteles',
            onPressed: widget.selectedHotel == null ? _reload : widget.onShowHotels ?? _reload,
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 112),
            itemCount: data.rooms.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _RoomsHeader(hotel: widget.selectedHotel, onShowHotels: widget.onShowHotels);
              }
              final room = data.rooms[index - 1];
              final hotel = data.hotelFor(room.hotelId) ?? widget.selectedHotel;
              final hotelName = hotel?.name ?? 'Hotel no identificado';
              return _RoomCard(
                room: room,
                hotelName: hotelName,
                onBook: () => _openBookingSheet(room, hotel),
              );
            },
          ),
        );
      },
    );
  }
}

class _RoomsData {
  final List<Hotel> hotels;
  final List<Room> rooms;

  const _RoomsData({required this.hotels, required this.rooms});

  Hotel? hotelFor(int hotelId) {
    for (final hotel in hotels) {
      if (hotel.id == hotelId) return hotel;
    }
    return null;
  }
}

class _RoomsHeader extends StatelessWidget {
  final Hotel? hotel;
  final VoidCallback? onShowHotels;

  const _RoomsHeader({required this.hotel, this.onShowHotels});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hotel != null)
            TextButton.icon(
              onPressed: onShowHotels,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Cambiar hotel'),
            ),
          SectionHeader(
            title: hotel == null ? 'Habitaciones disponibles' : 'Habitaciones en ${hotel!.name}',
            subtitle: hotel == null ? 'Reserva desde el cuarto que prefieras.' : hotel!.location,
          ),
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final Room room;
  final String hotelName;
  final VoidCallback onBook;

  const _RoomCard({
    required this.room,
    required this.hotelName,
    required this.onBook,
  });

  @override
  Widget build(BuildContext context) {
    final canBook = room.isAvailable;
    final imageUrl = _roomImageUrlStatic(room.id);
    return SmartCard(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              AppImage(
                url: imageUrl,
                height: 210,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                fallbackIcon: Icons.king_bed_outlined,
              ),
              Positioned(
                top: 14,
                right: 14,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(230),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.favorite_border, color: kSecondary, size: 21),
                ),
              ),
              Positioned(
                left: 14,
                bottom: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(150),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(canBook ? Icons.check_circle : Icons.info_outline, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        canBook ? 'Disponible ahora' : room.status,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(room.roomTypeName,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 4),
                          Text(hotelName, style: const TextStyle(color: kMuted)),
                        ],
                      ),
                    ),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star, color: kSecondary, size: 17),
                        SizedBox(width: 4),
                        Text('4.9', style: TextStyle(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(room.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: room.amenities.take(4).map((a) => Chip(label: Text(a))).toList(),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'S/ ${room.price.toStringAsFixed(0)}',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                            ),
                            const TextSpan(text: ' noche'),
                          ],
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: canBook ? onBook : null,
                      icon: const Icon(Icons.event_available),
                      label: const Text('Reservar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingSheet extends StatefulWidget {
  final ApiClient api;
  final Room room;
  final Hotel? hotel;

  const _BookingSheet({
    required this.api,
    required this.room,
    required this.hotel,
  });

  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  late final TextEditingController _guestName;
  late final TextEditingController _guestEmail;
  late final TextEditingController _checkIn;
  late final TextEditingController _checkOut;
  late final TextEditingController _cardNumber;
  late final TextEditingController _expiration;
  late final TextEditingController _cvv;
  late final TextEditingController _cardHolder;
  late DateTime _checkInDate;
  late DateTime _checkOutDate;
  int _step = 0;
  bool _loading = false;
  bool _payNow = true;

  String get _hotelName => widget.hotel?.name ?? 'Alojamiento';
  String get _hotelDestination => widget.hotel?.mapsQuery ?? _hotelName;
  String get _roomName => widget.room.roomTypeName.trim().isEmpty ? 'Habitación estándar' : widget.room.roomTypeName;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _checkInDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    _checkOutDate = _checkInDate.add(const Duration(days: 2));
    final user = SessionStore.currentUser;
    _guestName = TextEditingController(
      text: user == null ? 'Cliente' : (user.firstName.isNotEmpty ? user.firstName : user.username.split('@').first),
    );
    _guestEmail = TextEditingController(text: user?.email ?? '');
    _checkIn = TextEditingController(text: _formatDate(_checkInDate));
    _checkOut = TextEditingController(text: _formatDate(_checkOutDate));
    _cardNumber = TextEditingController();
    _expiration = TextEditingController();
    _cvv = TextEditingController();
    _cardHolder = TextEditingController();
  }

  @override
  void dispose() {
    _guestName.dispose();
    _guestEmail.dispose();
    _checkIn.dispose();
    _checkOut.dispose();
    _cardNumber.dispose();
    _expiration.dispose();
    _cvv.dispose();
    _cardHolder.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _prettyDate(DateTime date) {
    const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${date.day} ${months[date.month - 1]}';
  }

  int get _nights => _checkOutDate.difference(_checkInDate).inDays.clamp(1, 365);
  double get _total => widget.room.price * _nights;

  Future<void> _pickDate({required bool isCheckIn}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDate = isCheckIn ? today : _checkInDate.add(const Duration(days: 1));
    final initialDate = isCheckIn ? _checkInDate : _checkOutDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(firstDate) ? firstDate : initialDate,
      firstDate: firstDate,
      lastDate: firstDate.add(const Duration(days: 365)),
      helpText: isCheckIn ? 'Selecciona llegada' : 'Selecciona salida',
      cancelText: 'Cancelar',
      confirmText: 'Elegir',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: kPrimary,
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: kSecondary,
                ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    setState(() {
      if (isCheckIn) {
        _checkInDate = picked;
        _checkIn.text = _formatDate(picked);
        if (!_checkOutDate.isAfter(_checkInDate)) {
          _checkOutDate = _checkInDate.add(const Duration(days: 1));
          _checkOut.text = _formatDate(_checkOutDate);
        }
      } else {
        _checkOutDate = picked;
        _checkOut.text = _formatDate(picked);
      }
    });
  }

  void _nextStep() {
    if (_step == 0) {
      if (_guestName.text.trim().isEmpty) {
        showSmartSnack(context, 'Ingresa el nombre del huésped.');
        return;
      }
      if (!_checkOutDate.isAfter(_checkInDate)) {
        showSmartSnack(context, 'La salida debe ser posterior a la llegada.');
        return;
      }
    }
    if (_step == 1 && !_payNow) {
      _createBooking();
      return;
    }
    if (_step < 2) {
      setState(() => _step++);
      return;
    }
    _createBooking();
  }

  void _backStep() {
    if (_step == 0) {
      Navigator.pop(context);
      return;
    }
    setState(() => _step--);
  }

  Future<void> _createBooking() async {
    // The card is checked before booking, so a typo does not leave a Pending booking behind.
    CardDetails? card;
    if (_payNow) {
      final parsed = CardDetails.parse(
        number: _cardNumber.text,
        holderName: _cardHolder.text,
        expiry: _expiration.text,
        cvv: _cvv.text,
      );
      if (parsed.card == null) {
        showSmartSnack(context, parsed.error!);
        return;
      }
      card = parsed.card;
    }

    setState(() => _loading = true);
    try {
      final booking = await widget.api.createBooking(
        roomId: widget.room.id,
        checkIn: _checkInDate,
        checkOut: _checkOutDate,
        guestName: _guestName.text.trim(),
      );
      // The booking exists from here on: a declined card leaves it Pending, payable from Reservas.
      String? paymentError;
      if (card != null) {
        try {
          await widget.api.payWithCard(booking.id, card);
        } catch (e) {
          paymentError = errorText(e);
        }
      }
      if (!mounted) return;
      Navigator.pop(context, _BookingOutcome(booking, paid: card != null && paymentError == null, paymentError: paymentError));
    } catch (e) {
      if (!mounted) return;
      showSmartSnack(context, 'No se pudo completar la reserva: ${errorText(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.92;
    final title = switch (_step) {
      0 => 'Revisa y continúa',
      1 => 'Elige cuándo quieres pagar',
      _ => 'Agrega los datos de la tarjeta',
    };
    final buttonText = _step == 2 || (_step == 1 && !_payNow) ? 'Confirmar reserva' : 'Siguiente';

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(maxWidth: 560, maxHeight: maxSheetHeight),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: _step == 0 ? 'Cerrar' : 'Volver',
                        onPressed: _loading ? null : _backStep,
                        icon: Icon(_step == 0 ? Icons.close : Icons.arrow_back),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: _loading ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                _ProgressDots(step: _step),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: switch (_step) {
                        0 => _ReviewStep(
                            key: const ValueKey('review'),
                            hotelName: _hotelName,
                            roomName: _roomName,
                            room: widget.room,
                            checkInText: '${_prettyDate(_checkInDate)} – ${_prettyDate(_checkOutDate)} de ${_checkOutDate.year}',
                            nights: _nights,
                            total: _total,
                            guestName: _guestName,
                            guestEmail: _guestEmail,
                            onPickCheckIn: () => _pickDate(isCheckIn: true),
                            onPickCheckOut: () => _pickDate(isCheckIn: false),
                            destination: _hotelDestination,
                          ),
                        1 => _PaymentChoiceStep(
                            key: const ValueKey('choice'),
                            total: _total,
                            payNow: _payNow,
                            onChanged: (value) => setState(() => _payNow = value),
                          ),
                        _ => _CardDetailsStep(
                            key: const ValueKey('card'),
                            cardNumber: _cardNumber,
                            expiration: _expiration,
                            cvv: _cvv,
                            holder: _cardHolder,
                          ),
                      },
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: kLine)),
                  ),
                  child: SmartButton(text: buttonText, icon: Icons.arrow_forward, loading: _loading, dark: true, onPressed: _nextStep),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the booking sheet did: the booking always exists; the card payment may have failed.
class _BookingOutcome {
  final HotelBooking booking;
  final bool paid;
  final String? paymentError;

  const _BookingOutcome(this.booking, {required this.paid, this.paymentError});
}

class _ProgressDots extends StatelessWidget {
  final int step;

  const _ProgressDots({required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 4,
                margin: EdgeInsets.only(right: i == 2 ? 0 : 6),
                decoration: BoxDecoration(
                  color: i <= step ? kSecondary : kLine,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReviewStep extends StatelessWidget {
  final String hotelName;
  final String roomName;
  final Room room;
  final String checkInText;
  final int nights;
  final double total;
  final TextEditingController guestName;
  final TextEditingController guestEmail;
  final VoidCallback onPickCheckIn;
  final VoidCallback onPickCheckOut;
  final String destination;

  const _ReviewStep({
    super.key,
    required this.hotelName,
    required this.roomName,
    required this.room,
    required this.checkInText,
    required this.nights,
    required this.total,
    required this.guestName,
    required this.guestEmail,
    required this.onPickCheckIn,
    required this.onPickCheckOut,
    required this.destination,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: kLine),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  _roomImageUrlStatic(room.id),
                  width: 86,
                  height: 78,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 86,
                    height: 78,
                    color: kSoftBlue,
                    child: const Icon(Icons.bed_outlined, color: kPrimary),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(roomName, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(hotelName, style: const TextStyle(color: kMuted)),
                    const SizedBox(height: 6),
                    const Row(
                      children: [
                        Icon(Icons.star, size: 16, color: kSecondary),
                        SizedBox(width: 4),
                        Text('4.9', style: TextStyle(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _ReviewLine(
          title: 'Fechas',
          value: checkInText,
          actionText: 'Cambiar',
          onTap: onPickCheckIn,
        ),
        _ReviewLine(
          title: 'Huésped',
          value: guestName.text.trim().isEmpty ? '1 adulto' : guestName.text.trim(),
          actionText: 'Editar',
          onTap: null,
        ),
        _EditableGuestFields(name: guestName, email: guestEmail),
        _ReviewLine(
          title: 'Precio total',
          value: 'PEN S/ ${total.toStringAsFixed(2)}',
          actionText: 'Detalles',
          onTap: null,
        ),
        const SizedBox(height: 6),
        Text('$nights noches · S/ ${room.price.toStringAsFixed(0)} por noche', style: const TextStyle(color: kMuted)),
        const SizedBox(height: 24),
        Text('A dónde irás', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        RoutePreviewCard(destination: destination, height: 190, showDetails: false),
      ],
    );
  }
}

class _EditableGuestFields extends StatelessWidget {
  final TextEditingController name;
  final TextEditingController email;

  const _EditableGuestFields({required this.name, required this.email});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre del huésped', prefixIcon: Icon(Icons.person_outline))),
          const SizedBox(height: 10),
          // Guests always book with their account's e-mail: the backend ignores any other one.
          TextField(
            controller: email,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Correo',
              prefixIcon: Icon(Icons.mail_outline),
              helperText: 'La reserva y el pago se envían al correo de tu cuenta.',
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewLine extends StatelessWidget {
  final String title;
  final String value;
  final String actionText;
  final VoidCallback? onTap;

  const _ReviewLine({required this.title, required this.value, required this.actionText, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kLine))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(value, style: const TextStyle(fontSize: 16)),
              ],
            ),
          ),
          TextButton(onPressed: onTap, child: Text(actionText)),
        ],
      ),
    );
  }
}

class _PaymentChoiceStep extends StatelessWidget {
  final double total;
  final bool payNow;
  final ValueChanged<bool> onChanged;

  const _PaymentChoiceStep({super.key, required this.total, required this.payNow, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Elige cuándo quieres pagar', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 18),
        _PaymentOption(
          title: 'Paga S/ ${total.toStringAsFixed(2)} ahora',
          subtitle: 'Confirma tu reserva con tarjeta de crédito o débito.',
          selected: payNow,
          onTap: () => onChanged(true),
        ),
        _PaymentOption(
          title: 'Paga S/ 0 ahora',
          subtitle: 'Paga después de revisar tu solicitud.',
          selected: !payNow,
          onTap: () => onChanged(false),
        ),
      ],
    );
  }
}

class _PaymentOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentOption({required this.title, required this.subtitle, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          border: Border.all(color: selected ? kSecondary : kLine, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(subtitle, style: const TextStyle(color: kMuted, height: 1.3)),
                ],
              ),
            ),
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? kSecondary : kMuted, size: 30),
          ],
        ),
      ),
    );
  }
}

class _CardDetailsStep extends StatelessWidget {
  final TextEditingController cardNumber;
  final TextEditingController expiration;
  final TextEditingController cvv;
  final TextEditingController holder;

  const _CardDetailsStep({
    super.key,
    required this.cardNumber,
    required this.expiration,
    required this.cvv,
    required this.holder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Agrega un método de pago', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(border: Border.all(color: kSecondary, width: 1.3), borderRadius: BorderRadius.circular(22)),
          child: CardFields(number: cardNumber, holder: holder, expiry: expiration, cvv: cvv),
        ),
        const SizedBox(height: 14),
        const _CountryBox(),
        const SizedBox(height: 10),
        const Text('Pago de prueba: no se mueve dinero ni se guarda la tarjeta.', style: TextStyle(color: kMuted, fontSize: 12)),
      ],
    );
  }
}

class _CountryBox extends StatelessWidget {
  const _CountryBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(border: Border.all(color: kLine), borderRadius: BorderRadius.circular(18)),
      child: const Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('País/región', style: TextStyle(color: kMuted, fontSize: 12)),
                SizedBox(height: 2),
                Text('Perú', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Icon(Icons.keyboard_arrow_down),
        ],
      ),
    );
  }
}

String _roomImageUrlStatic(int id) {
  final images = [
    'https://images.unsplash.com/photo-1566665797739-1674de7a421a?auto=format&fit=crop&w=1000&q=80',
    'https://images.unsplash.com/photo-1611892440504-42a792e24d32?auto=format&fit=crop&w=1000&q=80',
    'https://images.unsplash.com/photo-1590490360182-c33d57733427?auto=format&fit=crop&w=1000&q=80',
    'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=1000&q=80',
  ];
  return images[id.abs() % images.length];
}
