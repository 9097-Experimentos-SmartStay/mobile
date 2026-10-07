
class AppUser {

  final int id;
  final String username;
  final String token;
  final String role;
  final int? hotelId;
  final int? chainId;
  final String firstName;
  final String email;

  const AppUser({
    required this.id,
    required this.username,
    required this.token,
    required this.role,
    this.hotelId,
    this.chainId,
    this.firstName = '',
    this.email = '',
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: readInt(json, 'id'),
      username: readString(json, 'username'),
      token: readString(json, 'token'),
      role: readString(json, 'role', fallback: 'guest'),
      hotelId: readNullableInt(json, 'hotelId'),
      chainId: readNullableInt(json, 'chainId'),
      firstName: readString(json, 'firstName'),
      email: readString(json, 'email', fallback: readString(json, 'username')),
    );
  }
}

/// Sign-in whose password was right but still needs a second factor (US-52): staff
/// accounts must use an authenticator app. [mfaToken] only works on the `/mfa/*` endpoints.
class MfaChallenge {
  final String mfaToken;

  /// True when the account has no authenticator yet and must enroll one first.
  final bool enrollmentRequired;
  final String email;

  const MfaChallenge({required this.mfaToken, required this.enrollmentRequired, required this.email});

  static MfaChallenge? fromJson(Map<String, dynamic> json) {
    final mfaToken = readString(json, 'mfaToken');
    final enrollment = json['mfaEnrollmentRequired'] == true;
    if (mfaToken.isEmpty || !(enrollment || json['mfaRequired'] == true)) return null;
    return MfaChallenge(mfaToken: mfaToken, enrollmentRequired: enrollment, email: readString(json, 'email'));
  }
}

/// Answer of `POST /authentication/mfa/enrollment`: what the authenticator app needs.
class MfaEnrollment {
  final String secret;
  final String otpAuthUri;
  final String issuer;
  final String accountName;

  const MfaEnrollment({
    required this.secret,
    required this.otpAuthUri,
    required this.issuer,
    required this.accountName,
  });

  factory MfaEnrollment.fromJson(Map<String, dynamic> json) {
    return MfaEnrollment(
      secret: readString(json, 'secret'),
      otpAuthUri: readString(json, 'otpAuthUri'),
      issuer: readString(json, 'issuer', fallback: 'SmartStay'),
      accountName: readString(json, 'accountName'),
    );
  }
}

/// Answer of `POST /authentication/sign-up`: the account exists but has no token yet,
/// the e-mail still has to be verified from the link the backend sent.
class SignUpResult {
  final int id;
  final String email;
  final bool emailVerified;
  final String message;

  const SignUpResult({
    required this.id,
    required this.email,
    required this.emailVerified,
    required this.message,
  });

  factory SignUpResult.fromJson(Map<String, dynamic> json) {
    return SignUpResult(
      id: readInt(json, 'id'),
      email: readString(json, 'email'),
      emailVerified: json['emailVerified'] == true,
      message: readString(
        json,
        'message',
        fallback: 'Cuenta creada. Revisa tu correo para verificarla.',
      ),
    );
  }
}

class Hotel {
  final int id;
  final int hostId;
  final String name;
  final String location;
  final String imageUrl;
  final String description;
  final double basePrice;
  final String type;
  final List<String> amenities;

  const Hotel({
    required this.id,
    required this.hostId,
    required this.name,
    required this.location,
    required this.imageUrl,
    required this.description,
    required this.basePrice,
    required this.type,
    required this.amenities,
  });

  factory Hotel.fromJson(Map<String, dynamic> json) {
    final name = readString(json, 'name', fallback: 'Alojamiento');
    final rawImage = readString(json, 'imageUrl');
    return Hotel(
      id: readInt(json, 'id'),
      hostId: readInt(json, 'hostId'),
      name: name,
      location: readString(json, 'location', fallback: 'Ubicación no disponible'),
      imageUrl: normalizedHotelImage(name, rawImage),
      description: readString(json, 'description', fallback: 'Sin descripción disponible.'),
      basePrice: readDouble(json, 'basePrice'),
      type: readString(json, 'type', fallback: 'Hotel'),
      amenities: readStringList(json, 'amenities'),
    );
  }

  String get mapsQuery => '$name, $location';
}

class Room {
  final int id;
  final int hotelId;
  final int roomTypeId;
  final String roomTypeName;
  final double price;
  final String description;
  final List<String> amenities;
  final String status;

  const Room({
    required this.id,
    required this.hotelId,
    required this.roomTypeId,
    required this.roomTypeName,
    required this.price,
    required this.description,
    required this.amenities,
    required this.status,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: readInt(json, 'id'),
      hotelId: readInt(json, 'hotelId'),
      roomTypeId: readInt(json, 'roomTypeId'),
      roomTypeName: readString(json, 'roomTypeName', fallback: 'Habitación'),
      price: readDouble(json, 'price'),
      description: readString(json, 'description', fallback: 'Sin descripción disponible.'),
      amenities: readStringList(json, 'amenities'),
      status: readString(json, 'status', fallback: 'Available'),
    );
  }

  bool get isAvailable {
    final normalized = status.toLowerCase();
    return normalized == 'clean' || normalized == 'available' || normalized == 'disponible';
  }
}

String readString(Map<String, dynamic> json, String key, {String fallback = ''}) {
  final value = json[key] ?? json[_upperFirst(key)];
  if (value == null) return fallback;
  return value.toString();
}

int readInt(Map<String, dynamic> json, String key, {int fallback = 0}) {
  final value = json[key] ?? json[_upperFirst(key)];
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}

int? readNullableInt(Map<String, dynamic> json, String key) {
  final value = json[key] ?? json[_upperFirst(key)];
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double readDouble(Map<String, dynamic> json, String key, {double fallback = 0}) {
  final value = json[key] ?? json[_upperFirst(key)];
  if (value == null) return fallback;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? fallback;
}

List<String> readStringList(Map<String, dynamic> json, String key) {
  final value = json[key] ?? json[_upperFirst(key)];
  if (value is List) return value.map((e) => e.toString()).toList();
  return const [];
}

String _upperFirst(String text) {
  if (text.isEmpty) return text;
  return text[0].toUpperCase() + text.substring(1);
}

String normalizedHotelImage(String hotelName, String rawUrl) {
  final name = hotelName.toLowerCase();
  if (name.contains('cusco') || name.contains('andean') || name.contains('lodge')) {
    return 'https://images.unsplash.com/photo-1526392060635-9d6019884377?auto=format&fit=crop&w=1200&q=80';
  }
  if (name.contains('bolivar') || name.contains('bolívar') || name.contains('grand')) {
    return 'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=1200&q=80';
  }
  if (rawUrl.trim().isNotEmpty && !rawUrl.contains('placehold.co')) return rawUrl;
  return 'https://images.unsplash.com/photo-1505693416388-ac5ce068fe85?auto=format&fit=crop&w=1200&q=80';
}
