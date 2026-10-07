import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../domain/models.dart';
import '../../domain/staff_models.dart';
import '../../domain/user_role.dart';
import '../../shared/ui.dart';
import 'staff_ui.dart';

/// Room map of the hotel: color by status, time in status and the maintenance alert (> 24 h).
/// A tap opens the room to change its status (only the transitions the API allows) and see its history.
class RoomMapPage extends StatefulWidget {
  const RoomMapPage({super.key});

  @override
  State<RoomMapPage> createState() => _RoomMapPageState();
}

class _RoomMapPageState extends State<RoomMapPage> {
  final _user = SessionStore.currentUser;
  RoomMap? _map;
  List<Hotel> _hotels = const [];
  int? _hotelId;
  bool _loading = true;
  String? _error;
  Timer? _clock;

  bool get _isChainAdmin => UserRole.normalize(_user?.role) == UserRole.chainAdmin;

  @override
  void initState() {
    super.initState();
    _start();
    // Time in status moves on by itself; the map is reloaded every 2 minutes to show changes made by others.
    var ticks = 0;
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      ticks += 1;
      if (ticks % 4 == 0) {
        _load(quiet: true);
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (_isChainAdmin) {
      // A chain_admin has no hotel of their own: they choose one (hotelId is required for them).
      try {
        _hotels = await ApiClient().getStaffHotels();
        _hotelId = _user?.hotelId ?? (_hotels.isEmpty ? null : _hotels.first.id);
      } catch (e) {
        if (mounted) setState(() => _error = 'No se pudieron cargar los hoteles: ${errorText(e)}');
      }
    }
    await _load();
  }

  Future<void> _load({bool quiet = false}) async {
    if (_isChainAdmin && _hotelId == null) {
      setState(() {
        _loading = false;
        _error ??= 'Elige un hotel para ver sus habitaciones.';
      });
      return;
    }
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final map = await ApiClient().getRoomMap(hotelId: _isChainAdmin ? _hotelId : null);
      if (mounted) setState(() => _map = map);
    } catch (e) {
      if (mounted && !quiet) setState(() => _error = 'No se pudo cargar el mapa: ${errorText(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openRoom(RoomMapEntry room) async {
    final changed = await showStaffSheet<String>(context, (_) => _RoomSheet(room: room, role: _user?.role));
    if (changed != null && mounted) {
      showSmartSnack(context, 'Habitación ${room.label}: ${roomStatusLabel(changed)}.');
      await _load(quiet: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final map = _map;
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Habitaciones', style: TextStyle(fontWeight: FontWeight.w900)),
            if (map != null && map.hotelName.isNotEmpty) Text(map.hotelName, style: const TextStyle(fontSize: 13, color: kMuted)),
          ],
        ),
        actions: [IconButton(tooltip: 'Actualizar', onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
          children: [
            if (_isChainAdmin && _hotels.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<int>(
                  initialValue: _hotelId,
                  decoration: const InputDecoration(labelText: 'Hotel', prefixIcon: Icon(Icons.apartment)),
                  items: [for (final hotel in _hotels) DropdownMenuItem(value: hotel.id, child: Text(hotel.name))],
                  onChanged: (id) {
                    setState(() => _hotelId = id);
                    _load();
                  },
                ),
              ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: kError))),
            if (map != null) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in map.summary.entries) _summaryChip(entry.key, entry.value),
                  if (map.overdueCount > 0)
                    StatusChip(label: '${map.overdueCount} en mantenimiento +24 h', color: const Color(0xFFB91C1C)),
                ],
              ),
              const SizedBox(height: 6),
              Text('Actualizado ${formatDateTime(map.generatedAt)}', style: const TextStyle(color: kMuted, fontSize: 12)),
              const SizedBox(height: 12),
              if (map.rooms.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Este hotel aún no tiene habitaciones.', textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 170,
                    mainAxisExtent: 128,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: map.rooms.length,
                  itemBuilder: (_, index) => _RoomTile(room: map.rooms[index], onTap: () => _openRoom(map.rooms[index])),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summaryChip(String status, int count) {
    final colors = roomStatusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(999), border: Border.all(color: colors.border)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(roomStatusIcon(status), size: 15, color: colors.foreground),
          const SizedBox(width: 5),
          Text('${roomStatusLabel(status)}: $count', style: TextStyle(color: colors.foreground, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  final RoomMapEntry room;
  final VoidCallback onTap;

  const _RoomTile({required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = roomStatusColors(room.status);
    final text = TextStyle(color: colors.foreground);
    return Material(
      color: colors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: colors.border, width: 2)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room.label, style: text.copyWith(fontSize: 24, fontWeight: FontWeight.w900)),
                  Text(room.roomTypeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.copyWith(fontSize: 12)),
                  const Spacer(),
                  Row(
                    children: [
                      Icon(roomStatusIcon(room.status), size: 15, color: colors.foreground),
                      const SizedBox(width: 4),
                      Text(roomStatusLabel(room.status), style: text.copyWith(fontWeight: FontWeight.w800, fontSize: 13)),
                    ],
                  ),
                  Text(formatDuration(room.timeInStatus()), style: text.copyWith(fontSize: 12)),
                ],
              ),
            ),
            if (room.maintenanceOverdue)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFB91C1C), borderRadius: BorderRadius.circular(999)),
                  child: const Text('+24 h', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A room: its status, a quick change to one of the allowed next statuses, and its history.
/// Pops with the new status when it changed.
class _RoomSheet extends StatefulWidget {
  final RoomMapEntry room;
  final String? role;

  const _RoomSheet({required this.room, required this.role});

  @override
  State<_RoomSheet> createState() => _RoomSheetState();
}

class _RoomSheetState extends State<_RoomSheet> {
  List<RoomStatusChange>? _history;
  String? _historyError;
  String? _pending;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final history = await ApiClient().getRoomStatusHistory(widget.room.id);
      if (mounted) setState(() => _history = history);
    } catch (e) {
      if (mounted) setState(() => _historyError = errorText(e));
    }
  }

  Future<void> _changeTo(String status) async {
    setState(() {
      _pending = status;
      _error = null;
    });
    try {
      await ApiClient().changeRoomStatus(widget.room.id, status);
      if (mounted) Navigator.pop(context, status);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final colors = roomStatusColors(room.status);
    final canChange = can(widget.role, Capability.changeRoomStatus);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader('Habitación ${room.label}', subtitle: room.roomTypeName),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(999), border: Border.all(color: colors.border)),
              child: Text(roomStatusLabel(room.status), style: TextStyle(color: colors.foreground, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Desde ${formatDateTime(room.statusSince)} (${formatDuration(room.timeInStatus())})',
                  style: const TextStyle(color: kMuted, fontSize: 13)),
            ),
          ],
        ),
        if (room.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(room.description, style: const TextStyle(color: kMuted))),
        if (room.maintenanceOverdue)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(14)),
            child: const Text('Lleva más de 24 horas en mantenimiento.', style: TextStyle(color: Color(0xFF991B1B), fontWeight: FontWeight.w700)),
          ),
        if (canChange) ...[
          const SizedBox(height: 18),
          const Text('Cambiar a', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (room.allowedNextStatuses.isEmpty)
            const Text('No hay cambios de estado posibles desde el actual.', style: TextStyle(color: kMuted))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final status in room.allowedNextStatuses)
                  OutlinedButton.icon(
                    onPressed: _pending == null ? () => _changeTo(status) : null,
                    icon: _pending == status
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(roomStatusIcon(status)),
                    label: Text(roomStatusLabel(status)),
                  ),
              ],
            ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: kError))),
        ],
        const SizedBox(height: 20),
        const Text('Historial', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        if (_historyError != null)
          Text('No se pudo cargar el historial: $_historyError', style: const TextStyle(color: kError))
        else if (_history == null)
          const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
        else if (_history!.isEmpty)
          const Text('Sin cambios registrados.', style: TextStyle(color: kMuted))
        else
          for (final change in _history!.take(20))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${roomStatusLabel(change.fromStatus)} → ${roomStatusLabel(change.toStatus)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([
                change.changedByEmail.isNotEmpty ? change.changedByEmail : 'Sistema',
                if (change.origin == 'CheckIn') 'check-in',
              ].join(' · ')),
              trailing: Text(formatDateTime(change.changedAt), style: const TextStyle(color: kMuted, fontSize: 12)),
            ),
      ],
    );
  }
}
