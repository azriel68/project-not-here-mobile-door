import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'app_controller.dart';
import 'main.dart' show coral, forest, ink, lime;

/// Reads the device position sent with door commands; [0, 0] when unknown.
typedef CoordinatesProvider = Future<List<double>> Function();

Future<List<double>> deviceCoordinates() async {
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) return [0, 0];
    final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    return [position.latitude, position.longitude];
  } catch (_) {
    return [0, 0];
  }
}

/// The app's only screen once signed in: open or close the accessible doors.
class DoorScreen extends StatefulWidget {
  const DoorScreen(
      {super.key,
      required this.controller,
      this.coordinates = deviceCoordinates});
  final AppController controller;
  final CoordinatesProvider coordinates;

  @override
  State<DoorScreen> createState() => _DoorScreenState();
}

class _DoorScreenState extends State<DoorScreen> with WidgetsBindingObserver {
  DoorAccess? _access;
  bool _loading = true;
  String? _error;
  int? _workingDoorId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the background: access depends on the time of day.
    if (state == AppLifecycleState.resumed) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final access = await widget.controller.loadDoors();
      if (mounted) {
        setState(() {
          _access = access;
          _error = null;
        });
      }
    } on AppException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Impossible de charger les portes.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _command(Door door, {required bool open}) async {
    setState(() => _workingDoorId = door.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final coordinates = await widget.coordinates();
      await widget.controller.setDoor(door.id,
          open: open, latitude: coordinates[0], longitude: coordinates[1]);
      messenger.showSnackBar(SnackBar(
          backgroundColor: forest,
          content: Text(open
              ? '${door.label} : ouverture envoyée.'
              : '${door.label} : fermeture envoyée.')));
    } on AppException catch (error) {
      messenger.showSnackBar(
          SnackBar(backgroundColor: coral, content: Text(error.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          backgroundColor: coral,
          content: Text('Impossible de commander cette porte.')));
    } finally {
      if (mounted) setState(() => _workingDoorId = null);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Se déconnecter')),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.logout();
  }

  @override
  Widget build(BuildContext context) {
    final cowork = widget.controller.selectedCowork;
    return Scaffold(
      appBar: AppBar(
        title: Text(cowork?.name ?? 'Accès',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
              tooltip: 'Actualiser',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
          IconButton(
              tooltip: 'Se déconnecter',
              onPressed: _logout,
              icon: const Icon(Icons.logout)),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - 26).clamp(0, 99999)),
                child: _body(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final access = _access;
    if (_loading && access == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && access == null) {
      return _Message(
          icon: Icons.cloud_off_outlined,
          title: 'Accès indisponible',
          message: _error!,
          onRetry: _load);
    }
    if (access == null || access.doors.isEmpty) {
      return _Message(
          icon: Icons.door_front_door_outlined,
          title: 'Aucune porte accessible',
          message:
              'Les portes liées à vos réservations du jour apparaîtront ici.',
          onRetry: _load);
    }
    final notice = !access.canOpen
        ? const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
                'L\'ouverture est disponible uniquement pendant la plage autorisée par votre réservation.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54)))
        : const SizedBox.shrink();

    if (access.doors.length == 1) {
      final door = access.doors.single;
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(door.label,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            notice,
            Expanded(child: _openButton(door, access, big: true)),
            const SizedBox(height: 16),
            Expanded(child: _closeButton(door, access, big: true)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        notice,
        for (final door in access.doors)
          Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const Icon(Icons.door_front_door_outlined, color: forest),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(door.label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 18))),
                  ]),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 76,
                    child: Row(children: [
                      Expanded(child: _openButton(door, access)),
                      const SizedBox(width: 12),
                      Expanded(child: _closeButton(door, access)),
                    ]),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _openButton(Door door, DoorAccess access, {bool big = false}) =>
      _DoorButton(
        key: ValueKey('open-${door.id}'),
        label: 'Ouvrir',
        icon: Icons.lock_open,
        background: forest,
        foreground: lime,
        big: big,
        working: _workingDoorId == door.id,
        onPressed: _workingDoorId != null || !access.canOpen
            ? null
            : () => _command(door, open: true),
      );

  Widget _closeButton(Door door, DoorAccess access, {bool big = false}) =>
      _DoorButton(
        key: ValueKey('close-${door.id}'),
        label: 'Fermer',
        icon: Icons.lock_outline,
        background: ink,
        foreground: Colors.white,
        big: big,
        working: _workingDoorId == door.id,
        onPressed: _workingDoorId != null || !access.canClose
            ? null
            : () => _command(door, open: false),
      );
}

class _DoorButton extends StatelessWidget {
  const _DoorButton(
      {super.key,
      required this.label,
      required this.icon,
      required this.background,
      required this.foreground,
      required this.big,
      required this.working,
      required this.onPressed});
  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final bool big;
  final bool working;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background.withOpacity(0.25),
          disabledForegroundColor: Colors.white70,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(big ? 28 : 18)),
        ),
        child: working
            ? SizedBox.square(
                dimension: big ? 36 : 22,
                child: CircularProgressIndicator(
                    strokeWidth: 3, color: foreground))
            : Flex(
                direction: big ? Axis.vertical : Axis.horizontal,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: big ? 64 : 26),
                  SizedBox(width: 8, height: big ? 12 : 0),
                  Text(label,
                      style: TextStyle(
                          fontSize: big ? 30 : 18,
                          fontWeight: FontWeight.w800)),
                ],
              ),
      );
}

class _Message extends StatelessWidget {
  const _Message(
      {required this.icon,
      required this.title,
      required this.message,
      this.onRetry});
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 12),
        child: Column(children: [
          Icon(icon, size: 44, color: forest.withOpacity(0.65)),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, height: 1.4)),
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'))
          ],
        ]),
      );
}
