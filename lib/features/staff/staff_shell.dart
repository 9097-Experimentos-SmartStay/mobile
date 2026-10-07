import 'package:flutter/material.dart';
import '../../core/session.dart';
import '../../domain/user_role.dart';
import '../../shared/ui.dart';
import 'room_map_page.dart';
import 'staff_bookings_page.dart';
import 'staff_guests_page.dart';
import 'staff_payments_page.dart';
import 'staff_today_page.dart';

class _Section {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Capability? capability;
  final Widget Function() build;

  const _Section(this.label, this.icon, this.activeIcon, this.capability, this.build);
}

/// Same sections as the staff area of the web app; each tab only shows when the role can open it.
final _sections = <_Section>[
  _Section('Hoy', Icons.today_outlined, Icons.today, null, () => const StaffTodayPage()),
  _Section('Reservas', Icons.calendar_month_outlined, Icons.calendar_month, Capability.viewBookings, () => const StaffBookingsPage()),
  _Section('Habitaciones', Icons.grid_view_outlined, Icons.grid_view_rounded, Capability.viewRoomMap, () => const RoomMapPage()),
  _Section('Pagos', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, Capability.viewPayments, () => const StaffPaymentsPage()),
  _Section('Huéspedes', Icons.badge_outlined, Icons.badge, Capability.viewGuests, () => const StaffGuestsPage()),
];

/// Home of the staff roles (reception, housekeeping, maintenance, admin, chain_admin).
class StaffShell extends StatefulWidget {
  const StaffShell({super.key});

  @override
  State<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends State<StaffShell> {
  late final List<_Section> _visible = _sections
      .where((section) => section.capability == null || can(SessionStore.currentUser?.role, section.capability!))
      .toList();

  /// Pages are built the first time their tab opens, then kept alive (no reload on every switch).
  late final List<Widget?> _pages = List.filled(_visible.length, null);
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    _pages[_index] ??= _visible[_index].build();
    return Scaffold(
      backgroundColor: kSurface,
      body: IndexedStack(
        index: _index,
        children: [for (final page in _pages) page ?? const SizedBox.shrink()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        backgroundColor: Colors.white,
        indicatorColor: kSoftBlue,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: [
          for (final section in _visible)
            NavigationDestination(icon: Icon(section.icon), selectedIcon: Icon(section.activeIcon), label: section.label),
        ],
      ),
    );
  }
}

/// Where a signed-in (or anonymous) user lands: staff roles get the staff app, everyone else the guest app.
Widget homeFor(Widget guestHome) => UserRole.isStaff(SessionStore.currentUser?.role) ? const StaffShell() : guestHome;
