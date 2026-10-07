import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../domain/staff_models.dart';
import '../../shared/ui.dart';
import 'staff_ui.dart';

/// Guest directory of the hotel (GET /guests: reception, admin, chain_admin).
class StaffGuestsPage extends StatefulWidget {
  const StaffGuestsPage({super.key});

  @override
  State<StaffGuestsPage> createState() => _StaffGuestsPageState();
}

class _StaffGuestsPageState extends State<StaffGuestsPage> {
  final _search = TextEditingController();
  List<GuestProfile> _guests = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final guests = await ApiClient().getGuests();
      guests.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
      if (mounted) setState(() => _guests = guests);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudieron cargar los huéspedes: ${errorText(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(GuestProfile guest) {
    showStaffSheet<void>(
      context,
      (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(guest.fullName, subtitle: guest.email),
          InfoRow('Teléfono', guest.phone.isEmpty ? '—' : guest.phone),
          InfoRow('Documento', guest.documentNumber.isEmpty ? '—' : '${guest.documentType} ${guest.documentNumber}'.trim()),
          InfoRow('Dirección', guest.address.isEmpty ? '—' : guest.address),
          InfoRow('Estado', guest.isActive ? 'Activo' : 'Inactivo'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = _search.text.trim().toLowerCase();
    final visible = text.isEmpty
        ? _guests
        : _guests.where((g) => '${g.fullName} ${g.email} ${g.phone} ${g.documentNumber}'.toLowerCase().contains(text)).toList();

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(title: const Text('Huéspedes', style: TextStyle(fontWeight: FontWeight.w900))),
      body: _loading && _guests.isEmpty
          ? const LoadingView(message: 'Cargando huéspedes...')
          : _error != null && _guests.isEmpty
              ? StaffErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                    children: [
                      TextField(
                        controller: _search,
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Nombre, correo, teléfono o documento'),
                      ),
                      const SizedBox(height: 8),
                      if (visible.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('No hay huéspedes que coincidan.', textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
                        ),
                      for (final guest in visible)
                        SmartCard(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          onTap: () => _open(guest),
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: kSoftBlue,
                              child: Text(guest.initials, style: const TextStyle(fontWeight: FontWeight.w800, color: kPrimaryDark)),
                            ),
                            title: Text(guest.fullName, style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text([guest.email, if (guest.phone.isNotEmpty) guest.phone].join(' · ')),
                            trailing: guest.isActive ? null : const StatusChip(label: 'Inactivo', color: kMuted),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
