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
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Greeting(controller: widget.controller),
              const SizedBox(height: 36),
              const _DoorBadge(size: 96),
              const SizedBox(height: 18),
              Text(door.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800, color: ink)),
              const SizedBox(height: 28),
              notice,
              _buttons(door, access, height: 92),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Greeting(controller: widget.controller),
            const SizedBox(height: 20),
            notice,
            for (final door in access.doors)
              Card(
                margin: const EdgeInsets.only(bottom: 14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        const _DoorBadge(size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(door.label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 17,
                                    color: ink))),
                      ]),
                      const SizedBox(height: 16),
                      _buttons(door, access, height: 60),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Open and close side by side, with a clear gap between them so a
  /// thumb cannot press both, and a size that is easy but deliberate to hit.
  Widget _buttons(Door door, DoorAccess access, {required double height}) {
    final working = _workingDoorId == door.id;
    final busy = _workingDoorId != null;
    return SizedBox(
      height: height,
      child: Row(children: [
        Expanded(
          child: _DoorButton(
            key: ValueKey('open-${door.id}'),
            label: 'Ouvrir',
            icon: Icons.lock_open_rounded,
            top: const Color(0xFF2C6E5F),
            bottom: forest,
            foreground: lime,
            working: working,
            onPressed: busy || !access.canOpen
                ? null
                : () => _command(door, open: true),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _DoorButton(
            key: ValueKey('close-${door.id}'),
            label: 'Fermer',
            icon: Icons.lock_rounded,
            top: const Color(0xFF3A4A44),
            bottom: ink,
            foreground: Colors.white,
            working: working,
            onPressed: busy || !access.canClose
                ? null
                : () => _command(door, open: false),
          ),
        ),
      ]),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bonjour ${controller.firstName},',
              key: const ValueKey('greeting'),
              style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w800, color: ink)),
          if (controller.identity.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.verified_user_outlined, size: 16, color: forest),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(controller.identity,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.black54))),
            ]),
          ],
        ],
      );
}

class _DoorBadge extends StatelessWidget {
  const _DoorBadge({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE6F5A8), lime]),
            boxShadow: [
              BoxShadow(
                  color: forest.withOpacity(0.18),
                  blurRadius: size / 5,
                  offset: Offset(0, size / 16)),
            ],
          ),
          child: Icon(Icons.door_front_door_rounded,
              size: size * 0.52, color: forest),
        ),
      );
}

/// A raised, glossy key: vertical gradient for volume, a soft highlight on
/// the upper half as a reflection, a drop shadow, and a pressed state that
/// sinks the button.
class _DoorButton extends StatefulWidget {
  const _DoorButton(
      {super.key,
      required this.label,
      required this.icon,
      required this.top,
      required this.bottom,
      required this.foreground,
      required this.working,
      required this.onPressed});
  final String label;
  final IconData icon;
  final Color top;
  final Color bottom;
  final Color foreground;
  final bool working;
  final VoidCallback? onPressed;

  @override
  State<_DoorButton> createState() => _DoorButtonState();
}

class _DoorButtonState extends State<_DoorButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onPressed != null && _pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final radius = BorderRadius.circular(20);
    final depth = _pressed ? 1.0 : 5.0;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onPressed,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled || widget.working ? 1 : 0.38,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            margin: EdgeInsets.only(top: 5 - depth, bottom: depth),
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [widget.top, widget.bottom]),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
              boxShadow: [
                // Solid base under the key: the relief.
                BoxShadow(
                    color: Color.lerp(widget.bottom, Colors.black, 0.45)!,
                    offset: Offset(0, depth)),
                // Soft cast shadow.
                BoxShadow(
                    color: widget.bottom.withOpacity(_pressed ? 0.15 : 0.3),
                    blurRadius: _pressed ? 4 : 14,
                    offset: Offset(0, depth + 3)),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(fit: StackFit.expand, children: [
                // Reflection on the upper half.
                Align(
                  alignment: Alignment.topCenter,
                  child: FractionallySizedBox(
                    heightFactor: 0.5,
                    widthFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withOpacity(0.22),
                              Colors.white.withOpacity(0.03),
                            ]),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: widget.working
                      ? SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: widget.foreground))
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(widget.icon,
                                color: widget.foreground, size: 24),
                            const SizedBox(width: 8),
                            Text(widget.label,
                                style: TextStyle(
                                    color: widget.foreground,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3)),
                          ],
                        ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
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
