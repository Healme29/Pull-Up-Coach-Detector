/// The two settings the app remembers: which lift you train, and whether to
/// spend your own gateway key or the free anonymous tier.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

class Prefs {
  Prefs._(this._sp);

  final SharedPreferences _sp;

  static const String _keyMode = 'lift_mode';
  static const String _keyApiKey = 'api_key';
  static const String _keyLaunchCount = 'launch_count';

  static Future<Prefs> load() async =>
      Prefs._(await SharedPreferences.getInstance());

  LiftMode get mode {
    final stored = _sp.getString(_keyMode);
    return stored == LiftMode.chinUp.name ? LiftMode.chinUp : LiftMode.pullUp;
  }

  Future<void> setMode(LiftMode mode) => _sp.setString(_keyMode, mode.name);

  /// Empty means the anonymous tier, which needs no account.
  String get apiKey => (_sp.getString(_keyApiKey) ?? '').trim();

  Future<void> setApiKey(String value) async {
    final clean = value.trim();
    if (clean.isEmpty) {
      await _sp.remove(_keyApiKey);
    } else {
      await _sp.setString(_keyApiKey, clean);
    }
  }

  bool get usingAnonymous => apiKey.isEmpty;

  int get launchCount => _sp.getInt(_keyLaunchCount) ?? 0;

  Future<void> bumpLaunches() => _sp.setInt(_keyLaunchCount, launchCount + 1);
}
