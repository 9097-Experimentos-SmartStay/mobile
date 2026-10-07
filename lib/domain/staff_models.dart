import 'models.dart';

/// Calendar day of the hotel as `yyyy-MM-dd`, the format the API uses for stays.
String formatApiDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Parses `yyyy-MM-dd` (or a full timestamp) to a date at midnight, or null.
DateTime? parseApiDate(String value) {
  final parsed = DateTime.tryParse(value);
  return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
}

DateTime? _readDateTime(Map<String, dynamic> json, String key) {
  final value = readString(json, key);
  return value.isEmpty ? null : DateTime.tryParse(value)?.toLocal();
}

/// Calendar-day arithmetic that never lands on 23:00 of the day before across a DST change.
DateTime addDays(DateTime date, int days) => DateTime(date.year, date.month, date.day + days);

DateTime get today {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// Lifecycle of a booking: Pending → (payment registered) → Confirmed → CheckedIn.
abstract final class BookingStatus {
  static const pending = 'Pending';
  static const confirmed = 'Confirmed';
  static const checkedIn = 'CheckedIn';
  static const cancelled = 'Cancelled';
  static const completed = 'Completed';
}

/// A booking (BookingResource, also CalendarBookingResource): guests read their own, staff those of their hotel.
class HotelBooking {
  final int id;
  final String code;
  final int? hotelId;
  final int roomId;
  final String roomNumber;
  final String guestName;
  final String guestEmail;
  final String guestPhone;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final int nights;
  final double pricePerNight;
  final double total;
  final String status;
  final DateTime? createdAt;
  final DateTime? paymentDueAt;
  final DateTime? confirmedAt;
  final DateTime? cancelledAt;
  final String cancellationReason;

  const HotelBooking({
    required this.id,
    required this.code,
    required this.hotelId,
    required this.roomId,
    required this.roomNumber,
    required this.guestName,
    required this.guestEmail,
    required this.guestPhone,
    required this.checkIn,
    required this.checkOut,
    required this.nights,
    required this.pricePerNight,
    required this.total,
    required this.status,
    required this.createdAt,
    required this.paymentDueAt,
    required this.confirmedAt,
    required this.cancelledAt,
    required this.cancellationReason,
  });

  factory HotelBooking.fromJson(Map<String, dynamic> json) {
    final checkIn = parseApiDate(readString(json, 'checkInDate'));
    final checkOut = parseApiDate(readString(json, 'checkOutDate'));
    final nights = readInt(json, 'nights',
        fallback: checkIn != null && checkOut != null ? checkOut.difference(checkIn).inDays : 0);
    final pricePerNight = readDouble(json, 'pricePerNight');
    return HotelBooking(
      id: readInt(json, 'id'),
      code: readString(json, 'code'),
      hotelId: readNullableInt(json, 'hotelId'),
      roomId: readInt(json, 'roomId'),
      roomNumber: readString(json, 'roomNumber'),
      guestName: readString(json, 'guestName'),
      guestEmail: readString(json, 'guestEmail'),
      guestPhone: readString(json, 'guestPhone'),
      checkIn: checkIn,
      checkOut: checkOut,
      nights: nights,
      pricePerNight: pricePerNight,
      total: readDouble(json, 'totalPrice', fallback: pricePerNight * nights),
      status: readString(json, 'status', fallback: BookingStatus.pending),
      createdAt: _readDateTime(json, 'createdAt'),
      paymentDueAt: _readDateTime(json, 'paymentDueAt'),
      confirmedAt: _readDateTime(json, 'confirmedAt'),
      cancelledAt: _readDateTime(json, 'cancelledAt'),
      cancellationReason: readString(json, 'cancellationReason'),
    );
  }

  String get reference => code.isNotEmpty ? code : '#$id';
  String get roomLabel => roomNumber.isNotEmpty ? roomNumber : '#$roomId';

  bool get isPending => status == BookingStatus.pending;
  bool get isConfirmed => status == BookingStatus.confirmed;
  bool get isCancelled => status == BookingStatus.cancelled;

  /// Cancelled automatically because nobody paid before the deadline ("Vencida").
  bool get isExpired => isCancelled && cancellationReason == 'PaymentNotReceived';

  /// A payment was registered at some point.
  bool get wasPaid => confirmedAt != null;

  /// Payment is registered while the booking is Pending (the payment confirms it).
  bool get canBePaid => isPending;

  /// Only Pending or Confirmed bookings can change dates or room.
  bool get canBeChanged => isPending || isConfirmed;

  /// Cancellation policy: Pending or Confirmed, and before the check-in day. Returns why not, or null.
  String? get cancellationBlock {
    if (!canBeChanged) return 'Solo se cancelan reservas pendientes o confirmadas.';
    if (checkIn != null && !today.isBefore(checkIn!)) return 'Ya no se puede cancelar: llegó el día de ingreso.';
    return null;
  }
}

/// One day of the reservations calendar: ids of the bookings that arrive, leave or stay that night.
class CalendarDay {
  final DateTime date;
  final List<int> arrivals;
  final List<int> departures;
  final List<int> inHouse;
  final int occupiedRooms;

  const CalendarDay({
    required this.date,
    required this.arrivals,
    required this.departures,
    required this.inHouse,
    required this.occupiedRooms,
  });

  factory CalendarDay.fromJson(Map<String, dynamic> json) {
    List<int> ids(String key) {
      final value = json[key];
      return value is List ? value.map((e) => int.tryParse(e.toString()) ?? 0).toList() : const [];
    }

    return CalendarDay(
      date: parseApiDate(readString(json, 'date')) ?? today,
      arrivals: ids('arrivals'),
      departures: ids('departures'),
      inHouse: ids('inHouse'),
      occupiedRooms: readInt(json, 'occupiedRooms'),
    );
  }

  bool get isQuiet => arrivals.isEmpty && departures.isEmpty && inHouse.isEmpty;
}

/// GET /bookings/calendar: active bookings that hold a night in the period, and one entry per day.
class BookingCalendar {
  final List<HotelBooking> bookings;
  final List<CalendarDay> days;
  final Map<int, HotelBooking> _byId;

  BookingCalendar({required this.bookings, required this.days})
      : _byId = {for (final booking in bookings) booking.id: booking};

  factory BookingCalendar.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> list(String key) {
      final value = json[key];
      return value is List ? value.map((e) => Map<String, dynamic>.from(e as Map)).toList() : const [];
    }

    return BookingCalendar(
      bookings: list('bookings').map(HotelBooking.fromJson).toList(),
      days: list('days').map(CalendarDay.fromJson).toList(),
    );
  }

  CalendarDay? dayOf(DateTime date) {
    for (final day in days) {
      if (day.date == date) return day;
    }
    return null;
  }

  List<HotelBooking> resolve(List<int> ids) =>
      ids.map((id) => _byId[id]).whereType<HotelBooking>().toList();
}

/// A room free for a whole stay (GET /rooms/available), with the total the booking will have.
class AvailableRoom {
  final int id;
  final int hotelId;
  final String number;
  final String roomTypeName;
  final double pricePerNight;
  final int nights;
  final double total;

  const AvailableRoom({
    required this.id,
    required this.hotelId,
    required this.number,
    required this.roomTypeName,
    required this.pricePerNight,
    required this.nights,
    required this.total,
  });

  factory AvailableRoom.fromJson(Map<String, dynamic> json) {
    return AvailableRoom(
      id: readInt(json, 'id'),
      hotelId: readInt(json, 'hotelId'),
      number: readString(json, 'number'),
      roomTypeName: readString(json, 'roomTypeName', fallback: 'Habitación'),
      pricePerNight: readDouble(json, 'pricePerNight'),
      nights: readInt(json, 'nights'),
      total: readDouble(json, 'totalPrice'),
    );
  }

  String get label => number.isNotEmpty ? number : '#$id';
}

/// How a guest paid outside the app. Every method except cash leaves an operation number.
abstract final class PaymentMethod {
  static const yape = 'Yape';
  static const plin = 'Plin';
  static const bankTransfer = 'BankTransfer';
  static const cash = 'Cash';
  static const cardAtFrontDesk = 'CardAtFrontDesk';

  static const all = [yape, plin, bankTransfer, cash, cardAtFrontDesk];

  static bool requiresOperationNumber(String? method) => method != null && method != cash;

  static String label(String method) => switch (method) {
        yape => 'Yape',
        plin => 'Plin',
        bankTransfer => 'Transferencia bancaria',
        cash => 'Efectivo',
        cardAtFrontDesk => 'Tarjeta en recepción',
        'Card' => 'Tarjeta (en línea)',
        _ => method,
      };
}

/// A payment registered by the hotel or made online (PaymentResource).
class StaffPayment {
  final int id;
  final int bookingId;
  final double amount;
  final String status;
  final String method;
  final String operationNumber;
  final String note;
  final DateTime? paymentDate;
  final DateTime? refundedAt;

  const StaffPayment({
    required this.id,
    required this.bookingId,
    required this.amount,
    required this.status,
    required this.method,
    required this.operationNumber,
    required this.note,
    required this.paymentDate,
    required this.refundedAt,
  });

  factory StaffPayment.fromJson(Map<String, dynamic> json) {
    return StaffPayment(
      id: readInt(json, 'id'),
      bookingId: readInt(json, 'bookingId'),
      amount: readDouble(json, 'amount'),
      status: readString(json, 'status'),
      method: readString(json, 'method'),
      operationNumber: readString(json, 'operationNumber'),
      note: readString(json, 'note'),
      paymentDate: _readDateTime(json, 'paymentDate'),
      refundedAt: _readDateTime(json, 'refundedAt'),
    );
  }

  bool get isRefunded => status == 'Refunded';
}

/// Operational status of a room.
abstract final class RoomStatus {
  static const available = 'Available';
  static const occupied = 'Occupied';
  static const cleaning = 'Cleaning';
  static const maintenance = 'Maintenance';

  static const order = [available, occupied, cleaning, maintenance];
}

/// A room on the hotel's room map: status, since when, and the statuses the API lets it move to.
class RoomMapEntry {
  final int id;
  final String number;
  final String roomTypeName;
  final String description;
  final String status;
  final DateTime? statusSince;
  final bool maintenanceOverdue;
  final List<String> allowedNextStatuses;

  const RoomMapEntry({
    required this.id,
    required this.number,
    required this.roomTypeName,
    required this.description,
    required this.status,
    required this.statusSince,
    required this.maintenanceOverdue,
    required this.allowedNextStatuses,
  });

  factory RoomMapEntry.fromJson(Map<String, dynamic> json) {
    return RoomMapEntry(
      id: readInt(json, 'id'),
      number: readString(json, 'number'),
      roomTypeName: readString(json, 'roomTypeName', fallback: 'Habitación'),
      description: readString(json, 'description'),
      status: readString(json, 'status', fallback: RoomStatus.available),
      statusSince: _readDateTime(json, 'statusSince'),
      maintenanceOverdue: json['maintenanceOverdue'] == true,
      allowedNextStatuses: readStringList(json, 'allowedNextStatuses'),
    );
  }

  String get label => number.isNotEmpty ? number : '#$id';

  Duration timeInStatus([DateTime? now]) {
    if (statusSince == null) return Duration.zero;
    final elapsed = (now ?? DateTime.now()).difference(statusSince!);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }
}

/// GET /rooms/map: every room of a hotel with its status.
class RoomMap {
  final int hotelId;
  final String hotelName;
  final DateTime? generatedAt;
  final List<RoomMapEntry> rooms;

  const RoomMap({required this.hotelId, required this.hotelName, required this.generatedAt, required this.rooms});

  factory RoomMap.fromJson(Map<String, dynamic> json) {
    final raw = json['rooms'];
    final rooms = raw is List
        ? raw.map((e) => RoomMapEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList()
        : <RoomMapEntry>[];
    rooms.sort((a, b) => _compareRoomNumbers(a.label, b.label));
    return RoomMap(
      hotelId: readInt(json, 'hotelId'),
      hotelName: readString(json, 'hotelName'),
      generatedAt: _readDateTime(json, 'generatedAt'),
      rooms: rooms,
    );
  }

  Map<String, int> get summary =>
      {for (final status in RoomStatus.order) status: rooms.where((room) => room.status == status).length};

  int get overdueCount => rooms.where((room) => room.maintenanceOverdue).length;
}

/// "2" < "10" < "10A": numbers read naturally, like a hotel floor plan.
int _compareRoomNumbers(String a, String b) {
  final na = int.tryParse(RegExp(r'^\d+').stringMatch(a) ?? '');
  final nb = int.tryParse(RegExp(r'^\d+').stringMatch(b) ?? '');
  if (na != null && nb != null && na != nb) return na.compareTo(nb);
  return a.toLowerCase().compareTo(b.toLowerCase());
}

/// One change in the status history of a room: who, when, from → to.
class RoomStatusChange {
  final String fromStatus;
  final String toStatus;
  final String origin;
  final DateTime? changedAt;
  final String changedByEmail;

  const RoomStatusChange({
    required this.fromStatus,
    required this.toStatus,
    required this.origin,
    required this.changedAt,
    required this.changedByEmail,
  });

  factory RoomStatusChange.fromJson(Map<String, dynamic> json) {
    return RoomStatusChange(
      fromStatus: readString(json, 'fromStatus'),
      toStatus: readString(json, 'toStatus'),
      origin: readString(json, 'origin'),
      changedAt: _readDateTime(json, 'changedAt'),
      changedByEmail: readString(json, 'changedByEmail'),
    );
  }
}

/// A guest of the hotel's directory (GuestProfileResource).
class GuestProfile {
  final String id;
  final String fullName;
  final String email;
  final String phone;
  final String documentType;
  final String documentNumber;
  final String address;
  final String status;

  const GuestProfile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.documentType,
    required this.documentNumber,
    required this.address,
    required this.status,
  });

  factory GuestProfile.fromJson(Map<String, dynamic> json) {
    final fullName = readString(json, 'fullName');
    final street = [readString(json, 'street'), readString(json, 'number')].where((s) => s.isNotEmpty).join(' ');
    return GuestProfile(
      id: readString(json, 'id'),
      fullName: fullName.isNotEmpty
          ? fullName
          : '${readString(json, 'firstName')} ${readString(json, 'lastName')}'.trim(),
      email: readString(json, 'email'),
      phone: readString(json, 'phone'),
      documentType: readString(json, 'documentType'),
      documentNumber: readString(json, 'documentNumber'),
      address: [street, readString(json, 'city'), readString(json, 'country')].where((s) => s.isNotEmpty).join(', '),
      status: readString(json, 'status', fallback: 'Active'),
    );
  }

  bool get isActive => status == 'Active';

  String get initials {
    final parts = fullName.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }
}

/// Card data for the simulated online payment (CardPaymentResource), validated like the web app:
/// 13–19 digits, holder name, an "MM/AA" expiry not in the past and a 3–4 digit CVV.
class CardDetails {
  final String number;
  final String holderName;
  final int expiryMonth;
  final int expiryYear;
  final String cvv;

  const CardDetails._(this.number, this.holderName, this.expiryMonth, this.expiryYear, this.cvv);

  /// The card, or the message of the first invalid field.
  static ({CardDetails? card, String? error}) parse({
    required String number,
    required String holderName,
    required String expiry,
    required String cvv,
    DateTime? now,
  }) {
    final digits = number.replaceAll(RegExp(r'[\s-]'), '');
    final holder = holderName.trim().replaceAll(RegExp(r'\s+'), ' ');
    final code = cvv.trim();
    final match = RegExp(r'^\s*(\d{1,2})\s*/\s*(\d{2})\s*$').firstMatch(expiry);
    final month = match == null ? null : int.parse(match.group(1)!);
    final year = match == null ? null : 2000 + int.parse(match.group(2)!);
    final current = now ?? DateTime.now();

    String? error;
    if (!RegExp(r'^\d{13,19}$').hasMatch(digits)) {
      error = 'El número de tarjeta debe tener entre 13 y 19 dígitos.';
    } else if (holder.length < 2) {
      error = 'Ingresa el nombre del titular, como figura en la tarjeta.';
    } else if (month == null || year == null || month < 1 || month > 12) {
      error = 'Ingresa el vencimiento como MM/AA.';
    } else if (year < current.year || (year == current.year && month < current.month)) {
      error = 'La tarjeta está vencida.';
    } else if (!RegExp(r'^\d{3,4}$').hasMatch(code)) {
      error = 'El CVV tiene 3 dígitos (4 en American Express).';
    }
    if (error != null) return (card: null, error: error);
    return (card: CardDetails._(digits, holder, month!, year!, code), error: null);
  }
}
