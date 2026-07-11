// Esta clase representa un usuario de la aplicación con sus propiedades y métodos asociados.
class AppUser {

  final int id;
  final String username;
  final String token;
  final String role;
  final int? hotelId;
  final int? chainId;

  // Constructor de la clase AppUser que inicializa todas las propiedades requeridas y opcionales.
  const AppUser({
    required this.id,
    required this.username,
    required this.token,
    required this.role,
    this.hotelId,
    this.chainId,
  });



  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: readInt(json, 'id'),
      username: readString(json, 'username'),
      token: readString(json, 'token'),
      role: readString(json, 'role', fallback: 'guest'),
      hotelId: readNullableInt(json, 'hotelId'),
      chainId: readNullableInt(json, 'chainId'),
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

class Booking {
  final int id;
  final int roomId;
  final String guestName;
  final String guestEmail;
  final String checkInDate;
  final String checkOutDate;
  final String status;

  const Booking({
    required this.id,
    required this.roomId,
    required this.guestName,
    required this.guestEmail,
    required this.checkInDate,
    required this.checkOutDate,
    required this.status,
  });

  factory Booking.fromJson(Map<String, dynamic> json) {
    return Booking(
      id: readInt(json, 'id'),
      roomId: readInt(json, 'roomId'),
      guestName: readString(json, 'guestName'),
      guestEmail: readString(json, 'guestEmail'),
      checkInDate: readString(json, 'checkInDate'),
      checkOutDate: readString(json, 'checkOutDate'),
      status: readString(json, 'status', fallback: 'Pending'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'roomId': roomId,
        'guestName': guestName,
        'guestEmail': guestEmail,
        'checkInDate': checkInDate,
        'checkOutDate': checkOutDate,
        'status': status,
      };

  Booking copyWith({String? status}) {
    return Booking(
      id: id,
      roomId: roomId,
      guestName: guestName,
      guestEmail: guestEmail,
      checkInDate: checkInDate,
      checkOutDate: checkOutDate,
      status: status ?? this.status,
    );
  }
}

class Payment {
  final int id;
  final int bookingId;
  final String transactionId;
  final double amount;
  final String status;
  final String cardNumberMasked;
  final String paymentDate;

  const Payment({
    required this.id,
    required this.bookingId,
    required this.transactionId,
    required this.amount,
    required this.status,
    required this.cardNumberMasked,
    required this.paymentDate,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: readInt(json, 'id'),
      bookingId: readInt(json, 'bookingId'),
      transactionId: readString(json, 'transactionId'),
      amount: readDouble(json, 'amount'),
      status: readString(json, 'status'),
      cardNumberMasked: readString(json, 'cardNumberMasked'),
      paymentDate: readString(json, 'paymentDate'),
    );
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
