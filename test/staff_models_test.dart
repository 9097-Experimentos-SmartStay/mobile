import 'package:flutter_test/flutter_test.dart';
import 'package:smart_stay/domain/staff_models.dart';
import 'package:smart_stay/domain/user_role.dart';

void main() {
  group('role matrix', () {
    test('reception works the desk but does not manage the hotel', () {
      expect(UserRole.isStaff('reception'), isTrue);
      expect(can('reception', Capability.registerPayments), isTrue);
      expect(can('reception', Capability.viewBookingCalendar), isTrue);
      expect(can('reception', Capability.viewGuests), isTrue);
      expect(can('reception', Capability.manageRooms), isFalse);
      expect(can('reception', Capability.manageUsers), isFalse);
    });

    test('housekeeping only reads bookings and works the rooms', () {
      expect(can('housekeeping', Capability.viewBookings), isTrue);
      expect(can('housekeeping', Capability.changeRoomStatus), isTrue);
      expect(can('housekeeping', Capability.registerPayments), isFalse);
      expect(can('housekeeping', Capability.viewPayments), isFalse);
    });

    test('guests and unknown roles are not staff', () {
      expect(UserRole.isStaff('guest'), isFalse);
      expect(UserRole.isStaff(null), isFalse);
      expect(UserRole.isStaff('Chain-Admin'), isTrue);
      expect(can('nobody', Capability.viewBookings), isFalse);
    });
  });

  test('BookingResource is read with its code, room number and total', () {
    final booking = HotelBooking.fromJson({
      'id': 7,
      'code': 'SS-AB12CD34',
      'hotelId': 1,
      'roomId': 3,
      'roomNumber': '204',
      'guestName': 'Ana Pérez',
      'guestEmail': 'ana@example.com',
      'checkInDate': '2030-03-10',
      'checkOutDate': '2030-03-13',
      'nights': 3,
      'pricePerNight': 120,
      'totalPrice': 360,
      'status': 'Pending',
      'paymentDueAt': '2030-03-01T15:00:00Z',
    });
    expect(booking.reference, 'SS-AB12CD34');
    expect(booking.roomLabel, '204');
    expect(booking.total, 360);
    expect(booking.checkIn, DateTime(2030, 3, 10));
    expect(booking.canBePaid, isTrue);
    expect(booking.cancellationBlock, isNull);
  });

  test('a cancelled booking nobody paid is expired, and cannot be cancelled again', () {
    final booking = HotelBooking.fromJson({
      'id': 1,
      'roomId': 2,
      'checkInDate': '2030-01-01',
      'checkOutDate': '2030-01-02',
      'status': 'Cancelled',
      'cancellationReason': 'PaymentNotReceived',
    });
    expect(booking.isExpired, isTrue);
    expect(booking.reference, '#1');
    expect(booking.cancellationBlock, isNotNull);
  });

  test('calendar days resolve their booking ids', () {
    final calendar = BookingCalendar.fromJson({
      'bookings': [
        {'id': 1, 'roomId': 1, 'guestName': 'A', 'checkInDate': '2030-05-01', 'checkOutDate': '2030-05-03', 'status': 'Confirmed'},
        {'id': 2, 'roomId': 2, 'guestName': 'B', 'checkInDate': '2030-04-29', 'checkOutDate': '2030-05-01', 'status': 'CheckedIn'},
      ],
      'days': [
        {'date': '2030-05-01', 'arrivals': [1], 'departures': [2], 'inHouse': [1], 'occupiedRooms': 1},
      ],
    });
    final day = calendar.dayOf(DateTime(2030, 5, 1))!;
    expect(calendar.resolve(day.arrivals).single.guestName, 'A');
    expect(calendar.resolve(day.departures).single.guestName, 'B');
    expect(calendar.dayOf(DateTime(2030, 5, 2)), isNull);
  });

  test('room map sorts rooms naturally and counts them per status', () {
    final map = RoomMap.fromJson({
      'hotelId': 1,
      'hotelName': 'Hotel',
      'rooms': [
        {'id': 1, 'number': '10', 'status': 'Occupied', 'allowedNextStatuses': ['Cleaning']},
        {'id': 2, 'number': '2', 'status': 'Available'},
        {'id': 3, 'number': '101', 'status': 'Maintenance', 'maintenanceOverdue': true},
      ],
    });
    expect(map.rooms.map((r) => r.label), ['2', '10', '101']);
    expect(map.summary, {'Available': 1, 'Occupied': 1, 'Cleaning': 0, 'Maintenance': 1});
    expect(map.overdueCount, 1);
    expect(map.rooms[1].allowedNextStatuses, ['Cleaning']);
  });

  test('only cash payments go without an operation number', () {
    expect(PaymentMethod.requiresOperationNumber(PaymentMethod.cash), isFalse);
    expect(PaymentMethod.requiresOperationNumber(PaymentMethod.yape), isTrue);
    expect(PaymentMethod.requiresOperationNumber(null), isFalse);
  });

  test('addDays and formatApiDate give calendar days', () {
    expect(formatApiDate(addDays(DateTime(2030, 12, 31), 1)), '2031-01-01');
    expect(formatApiDate(addDays(DateTime(2030, 3, 1), -1)), '2030-02-28');
  });
}
