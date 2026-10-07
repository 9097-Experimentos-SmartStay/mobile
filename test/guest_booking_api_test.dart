import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_stay/core/api_client.dart';
import 'package:smart_stay/core/session.dart';
import 'package:smart_stay/domain/models.dart';
import 'package:smart_stay/domain/staff_models.dart';

void main() {
  setUp(() {
    SessionStore.currentUser = const AppUser(id: 5, username: 'ana@example.com', token: 'jwt', role: 'guest');
  });

  group('CardDetails.parse', () {
    final now = DateTime(2026, 10, 6);
    ({CardDetails? card, String? error}) parse({String number = '4242 4242 4242 4242', String holder = 'Ana Perez', String expiry = '12/28', String cvv = '123'}) =>
        CardDetails.parse(number: number, holderName: holder, expiry: expiry, cvv: cvv, now: now);

    test('accepts a valid card and reads MM/AA as a four-digit year', () {
      final card = parse().card!;
      expect(card.number, '4242424242424242');
      expect(card.expiryMonth, 12);
      expect(card.expiryYear, 2028);
    });

    test('rejects each invalid field', () {
      expect(parse(number: '4242').error, contains('dígitos'));
      expect(parse(holder: ' ').error, contains('titular'));
      expect(parse(expiry: '13/28').error, contains('MM/AA'));
      expect(parse(expiry: '09/26').error, contains('vencida'));
      expect(parse(cvv: '12').error, contains('CVV'));
    });
  });

  test('createBooking sends the stay as calendar days and returns the backend booking', () async {
    late http.Request sent;
    final api = ApiClient(client: MockClient((request) async {
      sent = request;
      return http.Response(
        jsonEncode({'id': 9, 'code': 'SS-1', 'roomId': 3, 'checkInDate': '2030-01-02', 'checkOutDate': '2030-01-04', 'status': 'Pending', 'totalPrice': 240}),
        201,
      );
    }));

    final booking = await api.createBooking(roomId: 3, checkIn: DateTime(2030, 1, 2), checkOut: DateTime(2030, 1, 4), guestName: 'Ana');

    expect(sent.method, 'POST');
    expect(sent.url.path, endsWith('/bookings'));
    expect(sent.headers['Authorization'], 'Bearer jwt');
    expect(jsonDecode(sent.body), {'roomId': 3, 'checkInDate': '2030-01-02', 'checkOutDate': '2030-01-04', 'guestName': 'Ana'});
    expect(booking.reference, 'SS-1');
    expect(booking.total, 240);
  });

  test('a failed booking surfaces the backend message instead of a local fake booking', () async {
    final api = ApiClient(client: MockClient((_) async => http.Response(
          jsonEncode({'status': 409, 'detail': 'La habitación ya no está disponible para esas fechas.'}),
          409,
        )));

    expect(
      () => api.createBooking(roomId: 3, checkIn: DateTime(2030, 1, 2), checkOut: DateTime(2030, 1, 4)),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('ya no está disponible'))),
    );
  });

  test('payWithCard posts the card to the booking and surfaces a decline', () async {
    late http.Request sent;
    final api = ApiClient(client: MockClient((request) async {
      sent = request;
      return http.Response(jsonEncode({'detail': 'La tarjeta fue rechazada.', 'code': 'payment.card_declined'}), 409);
    }));
    final card = CardDetails.parse(number: '4000000000000002', holderName: 'Ana', expiry: '1/30', cvv: '123').card!;

    await expectLater(api.payWithCard(9, card), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'payment.card_declined')));
    expect(sent.url.path, endsWith('/bookings/9/payments/card'));
    expect(jsonDecode(sent.body), {
      'cardNumber': '4000000000000002',
      'cardHolderName': 'Ana',
      'expiryMonth': 1,
      'expiryYear': 2030,
      'cvv': '123',
    });
  });

  test('cancelling a booking that the backend refuses does not pretend it was cancelled', () async {
    final api = ApiClient(client: MockClient((_) async => http.Response(jsonEncode({'detail': 'Ya no se puede cancelar.'}), 409)));
    expect(() => api.cancelBooking(9), throwsA(isA<ApiException>()));
  });
}
