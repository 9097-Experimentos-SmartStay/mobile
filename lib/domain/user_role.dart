/// Role rules of the app, in ONE place. Port of `src/iam/domain/user-role.js` of the web
/// frontend, which mirrors the backend role matrix.
///
/// The backend is the one that enforces permissions (403). These rules only keep the UI
/// honest: never show a button whose request would be rejected.
abstract final class UserRole {
  static const guest = 'guest';
  static const reception = 'reception';
  static const housekeeping = 'housekeeping';
  static const maintenance = 'maintenance';
  static const admin = 'admin';
  static const chainAdmin = 'chain_admin';

  static const staff = [reception, housekeeping, maintenance, admin, chainAdmin];

  /// True for the roles that land in the staff app (everyone but guests).
  static bool isStaff(String? role) => staff.contains(normalize(role));

  /// The role in the API vocabulary (`Chain-Admin` → `chain_admin`), or null when unknown.
  static String? normalize(String? raw) {
    if (raw == null) return null;
    final role = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
    final alias = role == 'chainadmin' ? chainAdmin : role;
    return [guest, ...staff].contains(alias) ? alias : null;
  }
}

/// What a role can do. Same capabilities as the web app.
enum Capability {
  viewHotels,
  manageHotels,
  registerHotel,
  viewPaymentSettings,
  viewRooms,
  manageRooms,
  viewRoomMap,
  changeRoomStatus,
  createRoomTypes,
  manageMasterData,
  viewBookings,
  viewBookingCalendar,
  manageBookings,
  registerPayments,
  cancelBookings,
  viewPayments,
  viewAnalytics,
  viewGuests,
  manageUsers,
  viewAuditLog,
  controlRoomClimate,
  viewOperationsBoard,
  operateRoomDevices,
  injectRoomTelemetry,
}

const _deskRoles = [UserRole.reception, UserRole.admin, UserRole.chainAdmin];
const _adminRoles = [UserRole.admin, UserRole.chainAdmin];

const Map<Capability, List<String>> _capabilityRoles = {
  Capability.viewHotels: UserRole.staff,
  Capability.manageHotels: _adminRoles,
  Capability.registerHotel: _adminRoles,
  Capability.viewPaymentSettings: _deskRoles,
  Capability.viewRooms: UserRole.staff,
  Capability.manageRooms: _adminRoles,
  Capability.viewRoomMap: UserRole.staff,
  Capability.changeRoomStatus: UserRole.staff,
  Capability.createRoomTypes: _adminRoles,
  Capability.manageMasterData: [UserRole.chainAdmin],
  Capability.viewBookings: UserRole.staff,
  Capability.viewBookingCalendar: _deskRoles,
  Capability.manageBookings: _deskRoles,
  Capability.registerPayments: _deskRoles,
  Capability.cancelBookings: _deskRoles,
  Capability.viewPayments: _deskRoles,
  Capability.viewAnalytics: _adminRoles,
  Capability.viewGuests: _deskRoles,
  Capability.manageUsers: _adminRoles,
  Capability.viewAuditLog: _adminRoles,
  Capability.controlRoomClimate: [UserRole.guest],
  Capability.viewOperationsBoard: UserRole.staff,
  Capability.operateRoomDevices: [UserRole.maintenance, UserRole.admin, UserRole.chainAdmin],
  Capability.injectRoomTelemetry: _adminRoles,
};

bool can(String? role, Capability capability) =>
    (_capabilityRoles[capability] ?? const []).contains(UserRole.normalize(role));

/// Spanish name of a role, for headers and profile.
String roleLabel(String? role) {
  switch (UserRole.normalize(role)) {
    case UserRole.reception:
      return 'Recepción';
    case UserRole.housekeeping:
      return 'Limpieza';
    case UserRole.maintenance:
      return 'Mantenimiento';
    case UserRole.admin:
      return 'Administrador';
    case UserRole.chainAdmin:
      return 'Administrador de cadena';
    default:
      return 'Huésped';
  }
}
