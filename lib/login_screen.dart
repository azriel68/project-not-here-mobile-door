import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'main.dart' show forest, ink, lime;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _emailController;
  final _passwordController = TextEditingController();
  String? _error;
  bool _hidePassword = true;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.controller.email);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadCoworks();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadCoworks() async {
    setState(() => _error = null);
    try {
      await widget.controller.loadCoworks();
    } on AppException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Impossible de joindre cette adresse API.');
    }
  }

  Future<void> _signIn() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    try {
      await widget.controller
          .login(_emailController.text, _passwordController.text);
    } on AppException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'La connexion a échoué. Réessayez.');
    }
  }

  Future<void> _chooseCowork() async {
    var query = '';
    final selected = await showModalBottomSheet<Cowork>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(builder: (context, setSheetState) {
        final media = MediaQuery.of(context);
        final normalizedQuery = query.toLowerCase().trim();
        final matches = widget.controller.coworkers
            .where((item) =>
                item.name.toLowerCase().contains(normalizedQuery) ||
                item.hostname.toLowerCase().contains(normalizedQuery))
            .toList();
        final sheetHeight = (media.size.height -
                media.viewInsets.bottom -
                media.viewPadding.vertical -
                40)
            .clamp(220.0, media.size.height * 0.82)
            .toDouble();
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: SizedBox(
                height: sheetHeight,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                          child: Container(
                              width: 38,
                              height: 4,
                              decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(4)))),
                      const SizedBox(height: 22),
                      Text('Choisir un cowork',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 16),
                      TextField(
                          autofocus: true,
                          onChanged: (value) =>
                              setSheetState(() => query = value),
                          decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Rechercher par nom ou ville')),
                      const SizedBox(height: 12),
                      Expanded(
                        child: matches.isEmpty
                            ? const Center(child: Text('Aucun cowork trouvé.'))
                            : ListView.separated(
                                itemCount: matches.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final cowork = matches[index];
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                        backgroundColor: forest,
                                        foregroundColor: lime,
                                        child: Text(cowork.name.characters.first
                                            .toUpperCase())),
                                    title: Text(cowork.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                    subtitle: Text(cowork.hostname),
                                    trailing: const Icon(
                                        Icons.arrow_forward_ios,
                                        size: 16),
                                    onTap: () => Navigator.pop(context, cowork),
                                  );
                                },
                              ),
                      ),
                    ]),
              ),
            ),
          ),
        );
      }),
    );
    if (selected != null) {
      await widget.controller.selectCowork(selected);
      if (mounted) setState(() => _error = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final cowork = controller.selectedCowork;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
                children: [
                  Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.asset(
                        'assets/dollydesk_app_icon.png',
                        width: 42,
                        height: 42,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text('DollyDesk Door',
                        style: TextStyle(
                            fontSize: 21, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 34),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                        color: forest, borderRadius: BorderRadius.circular(22)),
                    child: Stack(children: [
                      Positioned(
                          right: -10,
                          top: -15,
                          child: Icon(Icons.grid_4x4,
                              size: 110,
                              color: Colors.white.withOpacity(0.06))),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                                width: 34,
                                height: 5,
                                decoration: BoxDecoration(
                                    color: lime,
                                    borderRadius: BorderRadius.circular(5))),
                            const SizedBox(height: 20),
                            const Text('Votre porte,\nen un geste.',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 31,
                                    height: 1.1,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 12),
                            Text(
                                'Connectez-vous pour ouvrir les portes de votre cowork.',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.75),
                                    height: 1.45)),
                          ]),
                    ]),
                  ),
                  const SizedBox(height: 25),
                  Row(children: [
                    const _SectionLabel('VOTRE COWORK'),
                    const Spacer(),
                    IconButton(
                      onPressed: controller.isBusy ? null : _loadCoworks,
                      tooltip: 'Actualiser la liste des coworks',
                      icon: controller.isBusy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: controller.coworkers.isEmpty || controller.isBusy
                        ? null
                        : _chooseCowork,
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 16),
                        alignment: Alignment.centerLeft,
                        side: const BorderSide(color: Color(0xFFD8E0D8))),
                    child: Row(children: [
                      Icon(
                          cowork == null
                              ? Icons.location_city_outlined
                              : Icons.place_outlined,
                          color: forest),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(
                              cowork?.name ??
                                  (controller.isBusy
                                      ? 'Chargement des coworks…'
                                      : 'Rechercher un cowork'),
                              style: TextStyle(
                                  color: cowork == null ? Colors.black54 : ink,
                                  fontWeight: cowork == null
                                      ? FontWeight.w400
                                      : FontWeight.w600))),
                      const Icon(Icons.expand_more),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  const _SectionLabel('VOTRE COMPTE'),
                  const SizedBox(height: 8),
                  TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                          labelText: 'Adresse e-mail',
                          prefixIcon: Icon(Icons.mail_outline))),
                  const SizedBox(height: 10),
                  TextField(
                      controller: _passwordController,
                      obscureText: _hidePassword,
                      onSubmitted: (_) => _signIn(),
                      decoration: InputDecoration(
                          labelText: 'Mot de passe',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                              icon: Icon(_hidePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => setState(
                                  () => _hidePassword = !_hidePassword)))),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600))
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed:
                        controller.isBusy || cowork == null ? null : _signIn,
                    style: FilledButton.styleFrom(
                        backgroundColor: forest,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))),
                    child: controller.isBusy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Se connecter',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 14),
                  Center(
                      child: Text(
                          '${controller.coworkers.length} cowork${controller.coworkers.length > 1 ? 's' : ''} disponible${controller.coworkers.length > 1 ? 's' : ''}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.black54))),
                ]),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Text(label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: forest, fontWeight: FontWeight.w800, letterSpacing: 1.0));
}
