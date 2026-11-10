// Integration test: the real ApiClient against a real SmartStay backend.
//
// It only runs against a local backend, never against production:
//   cd backend && docker compose -p smartstay-int up -d --build   (API on :10000)
//   flutter test test/integration \
//     --dart-define=API_BASE_URL=http://127.0.0.1:10000/api/v1 \
//     --dart-define=SMARTSTAY_API_CONTAINER=smartstay-int-api-1
//
// In Development the backend writes the e-mail verification link to its log, so the test reads the
// token from `docker logs` instead of needing a real mailbox.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smart_stay/core/api_client.dart';
import 'package:smart_stay/core/session.dart';
import 'package:smart_stay/domain/models.dart';

const _container = String.fromEnvironment('SMARTSTAY_API_CONTAINER', defaultValue: 'smartstay-api-1');

bool get _isLocalBackend {
  final uri = Uri.tryParse(ApiClient.baseUrl);
  return uri != null && (uri.host == 'localhost' || uri.host == '127.0.0.1');
}

/// Reads the verification token the backend logged for [email]'s verification link.
Future<String> _verificationTokenFor(String email) async {
  final logs = await Process.run('docker', ['logs', _container]);
  final text = '${logs.stdout}\n${logs.stderr}';
  final matches = RegExp(r'verify-email\?token=([A-Za-z0-9_\-]+)').allMatches(text).toList();
  expect(matches, isNotEmpty, reason: 'no verification link found in the logs of $_container');
  return matches.last.group(1)!;
}

Future<void> _verifyEmail(String token) async {
  final response = await http.post(
    Uri.parse('${ApiClient.baseUrl}/authentication/verify-email'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'token': token}),
  );
  expect(response.statusCode, anyOf(200, 204), reason: response.body);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding blocks real HTTP by default; this test must reach the local backend.
  HttpOverrides.global = null;
  // Only the platform keystore is simulated; every request below goes to the real backend.
  FlutterSecureStorage.setMockInitialValues({});

  final skip = _isLocalBackend ? null : 'Set API_BASE_URL to a local backend (see the header of this file).';
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final email = 'it.mobile.$stamp@example.com';
  const password = 'Sm4rt-Stay-Int-2026!';
  late ApiClient api;

  setUp(() {
    SessionStore.currentUser = null;
    api = ApiClient();
  });

  group('guest account flow against the real backend', () {
    test('sign-up creates an unverified account', () async {
      final result = await api.signUp(firstName: 'Ana', lastName: 'Perez', email: email, password: password);
      expect(result.email, email);
      expect(result.emailVerified, isFalse);
    }, skip: skip);

    test('sign-up with the same e-mail is rejected by the backend', () async {
      expect(
        () => api.signUp(firstName: 'Ana', lastName: 'Perez', email: email, password: password),
        throwsA(isA<ApiException>()),
      );
    }, skip: skip);

    test('sign-in before verifying the e-mail is refused with auth.email_not_verified', () async {
      await expectLater(
        api.signIn(email, password),
        throwsA(isA<ApiException>().having((e) => e.emailNotVerified, 'emailNotVerified', isTrue)),
      );
    }, skip: skip);

    test('sign-in with a wrong password is refused with 401', () async {
      await expectLater(
        api.signIn(email, 'Wrong-Pass-123!'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    }, skip: skip);

    test('after verifying the e-mail the guest signs in and reads their bookings', () async {
      await _verifyEmail(await _verificationTokenFor(email));

      final result = await api.signIn(email, password);
      expect(result, isA<AppUser>());
      final user = result as AppUser;
      expect(user.role, 'guest');
      expect(user.token, isNotEmpty);

      final bookings = await api.getBookings();
      expect(bookings, isEmpty);
    }, skip: skip);
  });
}
