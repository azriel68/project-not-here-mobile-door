import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_controller.dart';
import 'login_screen.dart';
import 'door_screen.dart';

const forest = Color(0xFF17463D);
const lime = Color(0xFFD8EF82);
const coral = Color(0xFFE88469);
const paper = Color(0xFFF3F5F1);
const ink = Color(0xFF192722);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  final baseApiUrl = dotenv.env['API_BASE_URL'];
  await dotenv.load(fileName: '.env.local', isOptional: true);
  final localApiUrl = dotenv.env['API_BASE_URL']?.trim();
  final productionApiUrl = baseApiUrl?.trim() ?? '';
  final buildApiUrl = apiBaseUrlOverride.trim();
  final preferredApiUrl = buildApiUrl.isNotEmpty
      ? buildApiUrl
      : localApiUrl?.isNotEmpty == true
          ? localApiUrl!
          : productionApiUrl;
  final apiUrl =
      await resolveReachableApiBaseUrl(preferredApiUrl, productionApiUrl);
  final controller = AppController(
      initialApiBaseUrl: apiUrl, productionApiBaseUrl: productionApiUrl);
  await controller.initialize();
  runApp(DollyDeskApp(controller: controller));
}

class DollyDeskApp extends StatelessWidget {
  const DollyDeskApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final colors =
        ColorScheme.fromSeed(seedColor: forest, surface: paper).copyWith(
      primary: forest,
      secondary: lime,
      error: coral,
      surface: paper,
    );
    return MaterialApp(
      title: 'DollyDesk Door',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colors,
        scaffoldBackgroundColor: paper,
        appBarTheme: const AppBarTheme(
            backgroundColor: paper,
            foregroundColor: ink,
            surfaceTintColor: Colors.transparent),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE0E6E0))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: forest, width: 1.5)),
        ),
        cardTheme: CardTheme(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFFE5EAE4))),
        ),
      ),
      // Temporary while the app is in development: shows which API is used.
      builder: kReleaseMode
          ? null
          : (context, child) => Stack(children: [
                child!,
                AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) => _ApiBadge(
                    production: controller.isProductionApi,
                    // On the login page, tapping TEST switches to production.
                    onTap: controller.canSwitchToProductionApi
                        ? controller.useProductionApi
                        : null,
                  ),
                ),
              ]),
      home: _AppRoot(controller: controller),
    );
  }
}

class _ApiBadge extends StatelessWidget {
  const _ApiBadge({required this.production, this.onTap});
  final bool production;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        ignoring: onTap == null,
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                margin: const EdgeInsets.only(top: 2),
                padding: EdgeInsets.symmetric(
                    horizontal: 8, vertical: onTap == null ? 2 : 4),
                decoration: BoxDecoration(
                  color: production ? coral : lime,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  production ? 'PRODUCTION' : 'TEST',
                  style: TextStyle(
                    color: production ? Colors.white : ink,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _AppRoot extends StatelessWidget {
  const _AppRoot({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (!controller.isReady)
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          if (controller.isAuthenticated)
            return DoorScreen(controller: controller);
          // Keyed on the API so switching to production reloads the coworks.
          return LoginScreen(
              key: ValueKey(controller.apiBaseUrl), controller: controller);
        },
      );
}
