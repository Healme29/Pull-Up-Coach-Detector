import 'package:flutter/material.dart';

import 'core/prefs.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

/// Lets the home screen refresh its history whenever a pushed screen closes.
final RouteObserver<PageRoute<dynamic>> routeObserver =
    RouteObserver<PageRoute<dynamic>>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await Prefs.load();
  await prefs.bumpLaunches();
  runApp(PullUpCoachApp(prefs: prefs));
}

class PullUpCoachApp extends StatelessWidget {
  const PullUpCoachApp({super.key, required this.prefs});

  final Prefs prefs;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pull-Up Coach',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    navigatorObservers: [routeObserver],
    home: HomePage(prefs: prefs),
  );
}
