import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../domain/staff_models.dart';
import '../../domain/user_role.dart';
import '../../shared/ui.dart';
import 'booking_sheets.dart';
import 'staff_ui.dart';

/// Hotel bookings: a searchable list and a month calendar (arrivals, departures, in house).
/// Reception and admins act on them; housekeeping and maintenance only read.
class StaffBookingsPage extends StatefulWidget {
  const StaffBookingsPage({super.key});

  @override
  State<StaffBookingsPage> createState() => _StaffBookingsPageState();
}

enum _Mode { list, calendar }

class _StaffBookingsPageState extends State<StaffBookingsPage> {
  final _role = SessionStore.currentUser?.role;
  final _calendarKey = GlobalKey<_BookingCalendarViewState>();
  late _Mode _mode = can(_role, Capability.viewBookingCalendar) ? _Mode.calendar : _Mode.list;
  final _listKey = GlobalKey<_BookingListViewState>();

  Future<void> _reloadAll() async {
    await Future.wait([
      if (_listKey.currentState != null) _listKey.currentState!.load(),
      if (_calendarKey.currentState != null) _calendarKey.currentState!.load(),
    ]);
  }

  Future<void> _newBooking() async {
    final created = await showNewBookingSheet(context);
    if (created != null) await _reloadAll();
  }

  @override
  Widget build(BuildContext context) {
    final canCalendar = can(_role, Capability.viewBookingCalendar);
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        title: const Text('Reservas', style: TextStyle(fontWeight: FontWeight.w900)),
        bottom: canCalendar
            ? PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: SegmentedButton<_Mode>(
                    segments: const [
                      ButtonSegment(value: _Mode.calendar, icon: Icon(Icons.calendar_month), label: Text('Calendario')),
                      ButtonSegment(value: _Mode.list, icon: Icon(Icons.list), label: Text('Lista')),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (value) => setState(() => _mode = value.first),
                  ),
                ),
              )
            : null,
      ),
      floatingActionButton: can(_role, Capability.manageBookings)
          ? FloatingActionButton.extended(
              onPressed: _newBooking,
              backgroundColor: kSecondary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Nueva reserva'),
            )
          : null,
      body: IndexedStack(
        index: _mode == _Mode.list ? 0 : 1,
        children: [
          _BookingListView(key: _listKey, onChanged: _reloadAll),
          canCalendar ? _BookingCalendarView(key: _calendarKey, onChanged: _reloadAll) : const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _BookingListView extends StatefulWidget {
  final Future<void> Function() onChanged;

  const _BookingListView({super.key, required this.onChanged});

  @override
  State<_BookingListView> createState() => _BookingListViewState();
}

/// Status filters of the list; "expired" is a cancelled booking nobody paid.
const _filters = <String?, String>{
  null: 'Todas',
  BookingStatus.pending: 'Pendientes',
  BookingStatus.confirmed: 'Confirmadas',
  BookingStatus.checkedIn: 'Hospedados',
  BookingStatus.cancelled: 'Canceladas',
  'Expired': 'Vencidas',
};

class _BookingListViewState extends State<_BookingListView> {
  final _search = TextEditingController();
  List<HotelBooking> _bookings = const [];
  String? _status;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    load();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bookings = await ApiClient().getBookings();
      if (mounted) setState(() => _bookings = bookings);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudieron cargar las reservas: ${errorText(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<HotelBooking> get _visible {
    final text = _search.text.trim().toLowerCase();
    return _bookings.where((b) {
      if (_status == 'Expired' && !b.isExpired) return false;
      if (_status != null && _status != 'Expired' && b.status != _status) return false;
      if (text.isEmpty) return true;
      return '${b.reference} ${b.guestName} ${b.guestEmail} ${b.roomLabel}'.toLowerCase().contains(text);
    }).toList();
  }

  Future<void> _open(HotelBooking booking) async {
    if (await openStaffBooking(context, booking)) await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _bookings.isEmpty) return const LoadingView(message: 'Cargando reservas...');
    if (_error != null && _bookings.isEmpty) return StaffErrorView(message: _error!, onRetry: load);

    final visible = _visible;
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          TextField(
            controller: _search,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Código, huésped, correo o habitación'),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in _filters.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: _status == entry.key,
                      onSelected: (_) => setState(() => _status = entry.key),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('No hay reservas que coincidan.', textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
            ),
          for (final booking in visible) StaffBookingCard(booking: booking, onTap: () => _open(booking)),
        ],
      ),
    );
  }
}

class StaffBookingCard extends StatelessWidget {
  final HotelBooking booking;
  final VoidCallback onTap;
  final Widget? leading;

  const StaffBookingCard({super.key, required this.booking, required this.onTap, this.leading});

  @override
  Widget build(BuildContext context) {
    return SmartCard(
      margin: const EdgeInsets.symmetric(vertical: 5),
      onTap: onTap,
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(booking.reference, style: const TextStyle(fontWeight: FontWeight.w900)),
                    const Spacer(),
                    BookingStatusChip(booking: booking),
                  ],
                ),
                const SizedBox(height: 6),
                Text(booking.guestName, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  'Hab. ${booking.roomLabel} · ${formatDay(booking.checkIn)} → ${formatDay(booking.checkOut)} · ${nightsLabel(booking.nights)}',
                  style: const TextStyle(color: kMuted, fontSize: 13),
                ),
                if (booking.isPending && booking.paymentDueAt != null)
                  Text('Pagar antes de ${formatDateTime(booking.paymentDueAt)}',
                      style: const TextStyle(color: Color(0xFFD97706), fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(formatMoney(booking.total), style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _BookingCalendarView extends StatefulWidget {
  final Future<void> Function() onChanged;

  const _BookingCalendarView({super.key, required this.onChanged});

  @override
  State<_BookingCalendarView> createState() => _BookingCalendarViewState();
}

class _BookingCalendarViewState extends State<_BookingCalendarView> {
  DateTime _month = DateTime(today.year, today.month);
  DateTime _selected = today;
  BookingCalendar? _calendar;
  bool _loading = true;
  String? _error;

  /// Six full weeks from the Monday before the 1st (42 days, under the 92-day limit).
  DateTime get _from => addDays(_month, 1 - _month.weekday);

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final calendar = await ApiClient().getBookingCalendar(_from, addDays(_from, 42));
      if (mounted) setState(() => _calendar = calendar);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo cargar el calendario: ${errorText(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _move(int months) {
    setState(() {
      _month = DateTime(_month.year, _month.month + months);
      _selected = _month.year == today.year && _month.month == today.month ? today : _month;
    });
    load();
  }

  Future<void> _open(HotelBooking booking) async {
    // Calendar entries carry the key facts only: the full booking (payment, contact) is read on open.
    HotelBooking full = booking;
    try {
      full = await ApiClient().getBooking(booking.id);
    } catch (_) {}
    if (!mounted) return;
    if (await openStaffBooking(context, full)) await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final calendar = _calendar;
    final day = calendar?.dayOf(_selected);
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        children: [
          Row(
            children: [
              IconButton(onPressed: () => _move(-1), icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: Text(
                  '${monthNames[_month.month - 1]} ${_month.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
              IconButton(onPressed: () => _move(1), icon: const Icon(Icons.chevron_right)),
            ],
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: kError))),
          _MonthGrid(
            from: _from,
            month: _month.month,
            selected: _selected,
            calendar: calendar,
            onSelect: (date) => setState(() => _selected = date),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Text(formatWeekday(_selected), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
              if (day != null) Text('${day.occupiedRooms} hab. ocupadas', style: const TextStyle(color: kMuted)),
            ],
          ),
          const SizedBox(height: 8),
          if (calendar != null && (day == null || day.isQuiet))
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Sin movimientos este día.', textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
            ),
          if (calendar != null && day != null) ...[
            ..._section('Llegadas', Icons.login, const Color(0xFF15803D), calendar.resolve(day.arrivals)),
            ..._section('Salidas', Icons.logout, const Color(0xFFB91C1C), calendar.resolve(day.departures)),
            ..._section(
              'Hospedados',
              Icons.hotel,
              kPrimaryDark,
              calendar.resolve(day.inHouse.where((id) => !day.arrivals.contains(id)).toList()),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _section(String title, IconData icon, Color color, List<HotelBooking> bookings) {
    if (bookings.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Text('$title (${bookings.length})', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
      ),
      for (final booking in bookings)
        StaffBookingCard(booking: booking, onTap: () => _open(booking), leading: Icon(icon, color: color)),
    ];
  }
}

class _MonthGrid extends StatelessWidget {
  final DateTime from;
  final int month;
  final DateTime selected;
  final BookingCalendar? calendar;
  final ValueChanged<DateTime> onSelect;

  const _MonthGrid({
    required this.from,
    required this.month,
    required this.selected,
    required this.calendar,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: kLine)),
      child: Column(
        children: [
          Row(
            children: [
              for (final initial in weekdayInitials)
                Expanded(child: Center(child: Text(initial, style: const TextStyle(color: kMuted, fontWeight: FontWeight.w700)))),
            ],
          ),
          const SizedBox(height: 4),
          for (var week = 0; week < 6; week++)
            Row(
              children: [
                for (var weekday = 0; weekday < 7; weekday++) _cell(addDays(from, week * 7 + weekday)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(DateTime date) {
    final day = calendar?.dayOf(date);
    final isSelected = date == selected;
    final inMonth = date.month == month;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onSelect(date),
        child: Container(
          height: 50,
          margin: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            color: isSelected ? kSecondary : (date == today ? kSoftBlue : null),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${date.day}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: isSelected ? Colors.white : (inMonth ? kSecondary : kMuted.withAlpha(110)),
                ),
              ),
              const SizedBox(height: 3),
              if (day != null && !day.isQuiet)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (day.arrivals.isNotEmpty) _dot(const Color(0xFF16A34A)),
                    if (day.departures.isNotEmpty) _dot(const Color(0xFFDC2626)),
                    if (day.inHouse.isNotEmpty) _dot(isSelected ? Colors.white : kPrimary),
                  ],
                )
              else
                const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot(Color color) => Container(
        width: 6,
        height: 6,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
