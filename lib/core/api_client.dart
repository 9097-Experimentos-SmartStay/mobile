import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/models.dart';
import '../domain/staff_models.dart';
import 'session.dart';

/// Error returned by the SmartStay API, already reduced to a message the UI can show.
class ApiException implements Exception {
  final int statusCode;
  final String message;

  /// Machine-readable code of the backend ProblemDetails, e.g. `auth.email_not_verified`.
  final String code;

  const ApiException(this.statusCode, this.message, {this.code = ''});

  bool get emailNotVerified => code == 'auth.email_not_verified';

  @override
  String toString() => message;
}

class ApiClient {
  static const String _rawBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://smartstay-movildev-api.onrender.com/api/v1',
  );

  final http.Client _client;

  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> _headers({bool auth = true}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final token = SessionStore.currentUser?.token;
    if (auth && token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Tolerates an `API_BASE_URL` given with or without a trailing slash.
  static String get baseUrl {
    final trimmed = _rawBaseUrl.trim();
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<dynamic> _decode(http.Response response) async {
    final body = response.body.trim();
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (body.isEmpty) return null;
      return jsonDecode(body);
    }
    throw _problem(response.statusCode, body);
  }

  /// Reads an RFC 7807 ProblemDetails: `detail` carries the message and `errors`
  /// lists one entry per invalid field on a 400.
  ApiException _problem(int statusCode, String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map) {
        final errors = parsed['errors'];
        if (errors is Map && errors.isNotEmpty) {
          final messages = errors.values
              .expand((value) => value is List ? value : [value])
              .map((value) => value.toString())
              .where((value) => value.isNotEmpty);
          if (messages.isNotEmpty) {
            return ApiException(
              statusCode,
              messages.join('\n'),
              code: parsed['code']?.toString() ?? '',
            );
          }
        }

        final message = parsed['detail']?.toString() ??
            parsed['message']?.toString() ??
            parsed['title']?.toString();
        if (message != null && message.isNotEmpty) {
          return ApiException(statusCode, message, code: parsed['code']?.toString() ?? '');
        }
      }
    } catch (_) {}

    return ApiException(statusCode, body.isEmpty ? 'Error HTTP $statusCode' : body);
  }

  /// Signs in. Returns the [AppUser] already saved in the session, or an [MfaChallenge]
  /// when the account (staff) still needs the authenticator code.
  Future<Object> signIn(String email, String password) async {
    final response = await _client.post(
      _uri('/authentication/sign-in'),
      headers: _headers(auth: false),
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = await _decode(response) as Map<String, dynamic>;
    final challenge = MfaChallenge.fromJson(data);
    if (challenge != null) return challenge;
    return _completeSignIn(data);
  }

  Future<AppUser> _completeSignIn(Map<String, dynamic> data) async {
    final user = AppUser.fromJson(data);
    if (user.token.isEmpty) {
      throw const ApiException(200, 'El servidor no devolvió una sesión válida. Intenta de nuevo.');
    }
    await SessionStore.save(user);
    return user;
  }

  /// Headers for the `/mfa/*` endpoints, which take the short-lived mfaToken instead of a session.
  Map<String, String> _mfaHeaders(String mfaToken) =>
      {..._headers(auth: false), 'Authorization': 'Bearer $mfaToken'};

  /// Second step of the sign-in: a 6-digit authenticator code or a one-time recovery code.
  Future<AppUser> verifyMfa(String mfaToken, {String? code, String? recoveryCode}) async {
    final response = await _client.post(
      _uri('/authentication/mfa/verify'),
      headers: _mfaHeaders(mfaToken),
      body: jsonEncode({
        if (code != null) 'code': code,
        if (recoveryCode != null) 'recoveryCode': recoveryCode,
      }),
    );
    return _completeSignIn(await _decode(response) as Map<String, dynamic>);
  }

  /// Starts enrolling an authenticator app; calling it again issues a new secret.
  Future<MfaEnrollment> startMfaEnrollment(String mfaToken) async {
    final response = await _client.post(
      _uri('/authentication/mfa/enrollment'),
      headers: _mfaHeaders(mfaToken),
    );
    return MfaEnrollment.fromJson(await _decode(response) as Map<String, dynamic>);
  }

  /// Confirms the enrollment with a first code: enables MFA, signs in and returns
  /// the recovery codes, which the backend shows only this once.
  Future<List<String>> confirmMfaEnrollment(String mfaToken, String code) async {
    final response = await _client.post(
      _uri('/authentication/mfa/enrollment/confirm'),
      headers: _mfaHeaders(mfaToken),
      body: jsonEncode({'code': code}),
    );
    final data = await _decode(response) as Map<String, dynamic>;
    await _completeSignIn(data);
    final codes = data['recoveryCodes'];
    return codes is List ? codes.map((c) => c.toString()).toList() : const [];
  }

  /// Creates a guest account. The backend answers 201 without a token and mails a
  /// verification link: the user can only sign in after opening it.
  Future<SignUpResult> signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    final response = await _client.post(
      _uri('/authentication/sign-up'),
      headers: _headers(auth: false),
      body: jsonEncode({
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'password': password,
        'role': 'guest',
      }),
    );
    final data = await _decode(response) as Map<String, dynamic>;
    return SignUpResult.fromJson(data);
  }

  Future<String> resendVerificationEmail(String email) async {
    final response = await _client.post(
      _uri('/authentication/verify-email/resend'),
      headers: _headers(auth: false),
      body: jsonEncode({'email': email}),
    );
    final data = await _decode(response);
    if (data is Map && data['message'] != null) return data['message'].toString();
    return 'Te enviamos un nuevo enlace de verificación.';
  }

  /// Loads hotels from the backend whenever the endpoint is public.
  ///
  /// Current Render backend may still protect this endpoint with JWT. In that
  /// case the app falls back to preview data so guests can still explore.
  /// After the backend is updated to allow public reads, this same Flutter code
  /// will automatically show real backend hotels and images before login.
  Future<List<Hotel>> getHotels() async {
    final authenticated = _hasSession;

    try {
      final response = await _client.get(
        _uri('/hotels'),
        headers: _headers(auth: authenticated),
      );
      final data = await _decode(response);
      if (data is List) {
        final hotels = data.map((e) => Hotel.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        if (hotels.isNotEmpty) return hotels;
      }
    } catch (_) {
      // The catalog should remain browsable even when Render is waking up or
      // the backend still requires a token for read-only endpoints.
    }

    return _previewHotels;
  }

  /// Loads rooms from the backend whenever the endpoint is public.
  /// Falls back to preview rooms only for guests while the backend still
  /// requires authentication for read-only hotel/room endpoints.
  Future<List<Room>> getRooms() async {
    final authenticated = _hasSession;

    try {
      final response = await _client.get(
        _uri('/rooms'),
        headers: _headers(auth: authenticated),
      );
      final data = await _decode(response);
      if (data is List) {
        final rooms = data.map((e) => Room.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        if (rooms.isNotEmpty) return rooms;
      }
    } catch (_) {
      // Keep the rooms experience usable while the public catalog endpoint is
      // being deployed or when Render has a temporary backend issue.
    }

    return _previewRooms;
  }

  Future<List<Room>> getRoomsByHotel(int hotelId) async {
    final rooms = await getRooms();
    return rooms.where((room) => room.hotelId == hotelId).toList();
  }

  /// The guest books a room for themselves: name and e-mail come from their account
  /// (`guestName` may override the name). Starts Pending with a 24 h payment deadline.
  Future<HotelBooking> createBooking({
    required int roomId,
    required DateTime checkIn,
    required DateTime checkOut,
    String guestName = '',
  }) async {
    return HotelBooking.fromJson(await _send('POST', '/bookings', {
      'roomId': roomId,
      'checkInDate': formatApiDate(checkIn),
      'checkOutDate': formatApiDate(checkOut),
      if (guestName.isNotEmpty) 'guestName': guestName,
    }));
  }

  /// POST /bookings/{id}/payments/card: guests only, own Pending booking; the amount is the booking
  /// total. The gateway is simulated and the card is never stored. A declined card answers 409
  /// `payment.card_declined` and the guest can retry.
  Future<void> payWithCard(int bookingId, CardDetails card) async {
    await _send('POST', '/bookings/$bookingId/payments/card', {
      'cardNumber': card.number,
      'cardHolderName': card.holderName,
      'expiryMonth': card.expiryMonth,
      'expiryYear': card.expiryYear,
      'cvv': card.cvv,
    });
  }

  Future<void> createProfile({
    required String firstName,
    required String lastName,
    required String email,
    required String street,
    required String number,
    required String city,
    required String postalCode,
    required String country,
  }) async {
    if (!_hasSession) {
      throw Exception('Inicia sesión para guardar tu perfil.');
    }

    final response = await _client.post(
      _uri('/guests'),
      headers: _headers(),
      body: jsonEncode({
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'street': street,
        'number': number,
        'city': city,
        'postalCode': postalCode,
        'country': country,
      }),
    );
    await _decode(response);
  }

  Future<void> changePassword(String currentPassword, String newPassword) async {
    if (!_hasSession) {
      throw Exception('Inicia sesión para cambiar tu contraseña.');
    }

    final response = await _client.post(
      _uri('/users/change-password'),
      headers: _headers(),
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );
    await _decode(response);
  }

  bool get _hasSession {
    final token = SessionStore.currentUser?.token;
    return token != null && token.isNotEmpty;
  }

  // --- Bookings, payments and hotel operations. Failures are never replaced by local or preview data:
  // the caller shows the backend's message.

  Uri _query(String path, Map<String, Object?> params) => _uri(path).replace(queryParameters: {
        for (final entry in params.entries)
          if (entry.value != null) entry.key: entry.value.toString(),
      });

  Future<dynamic> _get(Uri uri) async => _decode(await _client.get(uri, headers: _headers()));

  Future<Map<String, dynamic>> _send(String method, String path, [Map<String, Object?>? body]) async {
    final request = http.Request(method, _uri(path))
      ..headers.addAll(_headers())
      ..body = body == null ? '' : jsonEncode(body);
    final response = await http.Response.fromStream(await _client.send(request));
    final data = await _decode(response);
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  List<Map<String, dynamic>> _list(dynamic data) =>
      data is List ? data.map((e) => Map<String, dynamic>.from(e as Map)).toList() : const [];

  /// GET /bookings, scoped by the backend: a guest gets their own bookings, staff those of their
  /// hotel (every booking for a chain_admin). Newest first.
  Future<List<HotelBooking>> getBookings() async =>
      _list(await _get(_uri('/bookings'))).map(HotelBooking.fromJson).toList();

  Future<HotelBooking> getBooking(int id) async =>
      HotelBooking.fromJson(Map<String, dynamic>.from(await _get(_uri('/bookings/$id')) as Map));

  /// GET /bookings/calendar: [from] included, [to] excluded, at most 92 days.
  Future<BookingCalendar> getBookingCalendar(DateTime from, DateTime to, {int? hotelId}) async {
    final data = await _get(_query('/bookings/calendar', {
      'from': formatApiDate(from),
      'to': formatApiDate(to),
      'hotelId': hotelId,
    }));
    return BookingCalendar.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// GET /rooms/available: rooms free for the whole stay, with the total of the booking.
  Future<List<AvailableRoom>> getAvailableRooms(DateTime checkIn, DateTime checkOut, {int? hotelId}) async {
    final data = await _get(_query('/rooms/available', {
      'checkIn': formatApiDate(checkIn),
      'checkOut': formatApiDate(checkOut),
      'hotelId': hotelId,
    }));
    return _list(data).map(AvailableRoom.fromJson).toList();
  }

  /// Desk booking for a guest without an account (phone or walk-in). Starts Pending.
  Future<HotelBooking> createDeskBooking({
    required int roomId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String guestName,
    required String guestEmail,
    String guestPhone = '',
  }) async {
    return HotelBooking.fromJson(await _send('POST', '/bookings', {
      'roomId': roomId,
      'checkInDate': formatApiDate(checkIn),
      'checkOutDate': formatApiDate(checkOut),
      'guestName': guestName,
      'guestEmail': guestEmail,
      if (guestPhone.isNotEmpty) 'guestPhone': guestPhone,
    }));
  }

  /// PATCH /bookings/{id}: new dates and/or another room of the same hotel.
  Future<HotelBooking> changeBooking(int id, {DateTime? checkIn, DateTime? checkOut, int? roomId}) async {
    return HotelBooking.fromJson(await _send('PATCH', '/bookings/$id', {
      if (checkIn != null) 'checkInDate': formatApiDate(checkIn),
      if (checkOut != null) 'checkOutDate': formatApiDate(checkOut),
      if (roomId != null) 'roomId': roomId,
    }));
  }

  Future<HotelBooking> cancelBooking(int id) async =>
      HotelBooking.fromJson(await _send('POST', '/bookings/$id/cancel'));

  /// POST /bookings/{id}/payments: the amount is always the booking total; it becomes Confirmed.
  Future<StaffPayment> registerPayment(int bookingId, {required String method, String operationNumber = '', String note = ''}) async {
    return StaffPayment.fromJson(await _send('POST', '/bookings/$bookingId/payments', {
      'method': method,
      if (operationNumber.isNotEmpty) 'operationNumber': operationNumber,
      if (note.isNotEmpty) 'note': note,
    }));
  }

  /// GET /payments/booking/{id}: the completed (or refunded) payment of a booking.
  Future<StaffPayment> getPaymentOfBooking(int bookingId) async =>
      StaffPayment.fromJson(Map<String, dynamic>.from(await _get(_uri('/payments/booking/$bookingId')) as Map));

  /// GET /rooms/map: staff of a hotel may omit [hotelId]; a chain_admin must send it.
  Future<RoomMap> getRoomMap({int? hotelId}) async =>
      RoomMap.fromJson(Map<String, dynamic>.from(await _get(_query('/rooms/map', {'hotelId': hotelId})) as Map));

  /// PATCH /rooms/{id}/status: 409 when the transition is not allowed.
  Future<void> changeRoomStatus(int roomId, String status) async {
    await _send('PATCH', '/rooms/$roomId/status', {'status': status});
  }

  Future<List<RoomStatusChange>> getRoomStatusHistory(int roomId) async =>
      _list(await _get(_uri('/rooms/$roomId/status-history'))).map(RoomStatusChange.fromJson).toList();

  Future<List<GuestProfile>> getGuests() async =>
      _list(await _get(_uri('/guests'))).map(GuestProfile.fromJson).toList();

  /// Hotels without the guest preview fallback (chain_admin picks one for the room map).
  Future<List<Hotel>> getStaffHotels() async =>
      _list(await _get(_uri('/hotels'))).map(Hotel.fromJson).toList();

  static const List<Hotel> _previewHotels = [
    Hotel(
      id: 1,
      hostId: 1,
      name: 'Grand Hotel Bolivar',
      location: 'Jr. de la Unión 958, Lima, Peru',
      imageUrl: 'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=1200&q=80',
      description: 'Hotel histórico en el centro de Lima.',
      basePrice: 85.0,
      type: 'Hotel',
      amenities: ['Wifi', 'Restaurante', 'Bar'],
    ),
    Hotel(
      id: 2,
      hostId: 1,
      name: 'Cusco Andean Lodge',
      location: 'San Blas 123, Cusco, Peru',
      imageUrl: 'https://images.unsplash.com/photo-1526392060635-9d6019884377?auto=format&fit=crop&w=1200&q=80',
      description: 'Hospedaje andino cerca de las zonas más visitadas de Cusco.',
      basePrice: 320.0,
      type: 'Lodge',
      amenities: ['Desayuno', 'Wifi', 'Gimnasio'],
    ),
  ];

  static const List<Room> _previewRooms = [
    Room(
      id: 101,
      hotelId: 1,
      roomTypeId: 1,
      roomTypeName: 'Single Standard',
      price: 85.0,
      description: 'Habitación estándar con vista interior.',
      amenities: ['Wifi', 'TV'],
      status: 'Clean',
    ),
    Room(
      id: 102,
      hotelId: 1,
      roomTypeId: 2,
      roomTypeName: 'Double Deluxe',
      price: 150.0,
      description: 'Habitación doble con balcón y vista a la plaza.',
      amenities: ['Wifi', 'TV', 'Minibar'],
      status: 'Clean',
    ),
    Room(
      id: 201,
      hotelId: 2,
      roomTypeId: 3,
      roomTypeName: 'Presidential Suite',
      price: 320.0,
      description: 'Suite amplia con vista panorámica a la ciudad.',
      amenities: ['Jacuzzi', 'Wifi', 'Desayuno', 'Chimenea'],
      status: 'Dirty',
    ),
  ];
}
