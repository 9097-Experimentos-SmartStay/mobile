import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../domain/staff_models.dart';
import '../../domain/user_role.dart';
import '../../shared/ui.dart';
import '../client/client_shell.dart';
import 'booking_sheets.dart';
import 'staff_bookings_page.dart';
import 'staff_ui.dart';

/// Home of the staff app: what the shift needs today (arrivals, departures, guests in house)
/// and the rooms by status. Each block only shows when the role can read it.
class StaffTodayPage extends StatefulWidget {
  const StaffTodayPage({super.key});

  @override
  State<StaffTodayPage> createState() => _StaffTodayPageState();
}

class _StaffTodayPageState extends State<StaffTodayPage> {
  final _user = SessionStore.currentUser;
  BookingCalendar? _calendar;
  RoomMap? _rooms;
  String? _calendarError;
  String? _roomsError;
  bool _loading = true;

  bool get _canCalendar => can(_user?.role, Capability.viewBookingCalendar);
  // A chain_admin has no hotel of their own: the room map needs one, so it lives in its tab.
  bool get _canRooms => can(_user?.role, Capability.viewRoomMap) && _user?.hotelId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final api = ApiClient();
    await Future.wait([
      if (_canCalendar)
        api.getBookingCalendar(today, addDays(today, 1)).then(
              (value) => _calendar = value,
              onError: (Object e) => _calendarError = errorText(e),
            ),
      if (_canRooms)
        api.getRoomMap().then(
              (value) => _rooms = value,
              onError: (Object e) => _roomsError = errorText(e),
            ),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _logout() async {
    await SessionStore.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const ClientShell()), (_) => false);
  }

  Future<void> _open(HotelBooking booking) async {
    HotelBooking full = booking;
    try {
      full = await ApiClient().getBooking(booking.id);
    } catch (_) {}
    if (!mounted) return;
    if (await openStaffBooking(context, full)) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final name = _user?.firstName.isNotEmpty == true ? _user!.firstName : (_user?.email ?? '');
    final day = _calendar?.dayOf(today);
    final calendar = _calendar;

    return Scaffold(
      backgroundColor: kSurface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: kSecondary, borderRadius: BorderRadius.circular(28)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hola, $name', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 4),
                          Text('${roleLabel(_user?.role)} · ${formatWeekday(today)}', style: const TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      onSelected: (_) => _logout(),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout), title: Text('Cerrar sesión'))),
                      ],
                    ),
                  ],
                ),
              ),
              if (_loading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 2)),
              if (_canCalendar) ...[
                const SizedBox(height: 18),
                const Text('Hoy en el hotel', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 10),
                if (_calendarError != null)
                  Text('No se pudo cargar el día: $_calendarError', style: const TextStyle(color: kError))
                else
                  Row(
                    children: [
                      _Metric(label: 'Llegadas', value: day?.arrivals.length, icon: Icons.login, color: const Color(0xFF15803D)),
                      _Metric(label: 'Salidas', value: day?.departures.length, icon: Icons.logout, color: const Color(0xFFB91C1C)),
                      _Metric(label: 'Hospedados', value: day?.inHouse.length, icon: Icons.hotel, color: kPrimaryDark),
                    ],
                  ),
                if (calendar != null && day != null) ...[
                  ..._section('Llegan hoy', calendar.resolve(day.arrivals)),
                  ..._section('Salen hoy', calendar.resolve(day.departures)),
                  if (day.arrivals.isEmpty && day.departures.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Hoy no hay llegadas ni salidas.', textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
                    ),
                ],
              ],
              if (_canRooms) ...[
                const SizedBox(height: 18),
                const Text('Habitaciones', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 10),
                if (_roomsError != null)
                  Text('No se pudo cargar el estado de las habitaciones: $_roomsError', style: const TextStyle(color: kError))
                else if (_rooms != null) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in _rooms!.summary.entries)
                        Builder(builder: (context) {
                          final colors = roomStatusColors(entry.key);
                          return Container(
                            width: 150,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: colors.background,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: colors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${entry.value}', style: TextStyle(color: colors.foreground, fontSize: 24, fontWeight: FontWeight.w900)),
                                Text(roomStatusLabel(entry.key), style: TextStyle(color: colors.foreground, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                  if (_rooms!.overdueCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: StatusChip(
                        label: '${_rooms!.overdueCount} habitación(es) llevan más de 24 h en mantenimiento',
                        color: const Color(0xFFB91C1C),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _section(String title, List<HotelBooking> bookings) {
    if (bookings.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 2),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      for (final booking in bookings) StaffBookingCard(booking: booking, onTap: () => _open(booking)),
    ];
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final int? value;
  final IconData icon;
  final Color color;

  const _Metric({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: kLine)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(value?.toString() ?? '—', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            Text(label, style: const TextStyle(color: kMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
