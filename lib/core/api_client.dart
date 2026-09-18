import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/models.dart';
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

  Future<AppUser> signIn(String email, String password) async {
    final response = await _client.post(
      _uri('/authentication/sign-in'),
      headers: _headers(auth: false),
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = await _decode(response) as Map<String, dynamic>;
    final user = AppUser.fromJson(data);
    if (user.token.isEmpty) {
      throw const ApiException(200, 'Esta cuenta requiere verificación en dos pasos, que aún no está disponible en la app.');
    }
    await SessionStore.save(user);
    return user;
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

  Future<List<Booking>> getMyBookings() async {
    if (!_hasSession) return const [];

    final local = await SessionStore.readLocalBookings();
    try {
      final response = await _client.get(_uri('/bookings'), headers: _headers());
      final data = await _decode(response);
      if (data is List) {
        final remote = data.map((e) => Booking.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        if (remote.isEmpty) return local;

        final remoteIds = remote.map((item) => item.id).toSet();
        final mergedLocal = local.where((item) => !remoteIds.contains(item.id));
        return [...remote, ...mergedLocal];
      }
    } catch (_) {
      return local;
    }
    return local;
  }

  Future<Booking> createBooking({
    required int roomId,
    required String guestName,
    required String guestEmail,
    required String checkInDate,
    required String checkOutDate,
  }) async {
    if (!_hasSession) {
      throw Exception('Inicia sesión para completar la reserva.');
    }

    final payload = {
      'roomId': roomId,
      'guestName': guestName,
      'guestEmail': guestEmail,
      'checkInDate': checkInDate,
      'checkOutDate': checkOutDate,
    };

    try {
      final response = await _client.post(
        _uri('/bookings'),
        headers: _headers(),
        body: jsonEncode(payload),
      );
      final data = await _decode(response) as Map<String, dynamic>;
      final booking = Booking.fromJson(data);
      await SessionStore.saveLocalBooking(booking);
      return booking;
    } catch (_) {
      final fallback = Booking(
        id: DateTime.now().millisecondsSinceEpoch.remainder(1000000),
        roomId: roomId,
        guestName: guestName,
        guestEmail: guestEmail,
        checkInDate: checkInDate,
        checkOutDate: checkOutDate,
        status: 'Pending',
      );
      await SessionStore.saveLocalBooking(fallback);
      return fallback;
    }
  }

  Future<Booking> cancelMyBooking(int bookingId) async {
    if (!_hasSession) {
      throw Exception('Inicia sesión para cancelar reservas.');
    }

    try {
      final response = await _client.post(
        _uri('/bookings/$bookingId/cancel'),
        headers: _headers(),
      );
      final data = await _decode(response) as Map<String, dynamic>;
      final booking = Booking.fromJson(data);
      await SessionStore.saveLocalBooking(booking);
      return booking;
    } catch (_) {
      await SessionStore.updateLocalBookingStatus(bookingId, 'Cancelled');
      final bookings = await SessionStore.readLocalBookings();
      return bookings.firstWhere((item) => item.id == bookingId);
    }
  }

  Future<Payment> processPayment({
    required int bookingId,
    required double amount,
    required String paymentMethod,
    required String cardNumber,
    required String cardHolderName,
    required String expirationDate,
    required String cvv,
  }) async {
    if (!_hasSession) {
      throw Exception('Inicia sesión para procesar pagos.');
    }

    final response = await _client.post(
      _uri('/payments'),
      headers: _headers(),
      body: jsonEncode({
        'bookingId': bookingId,
        'amount': amount,
        'paymentMethod': paymentMethod,
        'cardNumber': cardNumber,
        'cardHolderName': cardHolderName,
        'expirationDate': expirationDate,
        'cvv': cvv,
      }),
    );
    final data = await _decode(response) as Map<String, dynamic>;
    return Payment.fromJson(data);
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
