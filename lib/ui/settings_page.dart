/// Settings: which gateway key to use, what the free tier allows, and what is
/// stored on the phone.
library;

import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/prefs.dart';
import '../core/store.dart';
import '../core/video_toolkit.dart' show VideoToolkit;
import 'format.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.prefs, required this.store});

  final Prefs prefs;
  final RunStore store;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _key;
  bool _obscure = true;
  int _bytes = 0;
  int _runs = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _key = TextEditingController(text: widget.prefs.apiKey);
    _loadStorage();
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _loadStorage() async {
    try {
      final bytes = await widget.store.totalBytes();
      final runs = await widget.store.history();
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _runs = runs.length;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveKey() async {
    await widget.prefs.setApiKey(_key.text);
    if (!mounted) return;
    setState(() {});
    _toast(
      widget.prefs.usingAnonymous
          ? 'Cleared. The free anonymous tier will be used.'
          : 'Key saved on this phone.',
    );
  }

  Future<void> _useFreeTier() async {
    _key.clear();
    await widget.prefs.setApiKey('');
    if (!mounted) return;
    setState(() {});
    _toast('Using the free anonymous tier.');
  }

  Future<void> _clearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete every saved run?'),
        content: const Text(
          'Clips, poses and results will be removed from this phone. This '
          'cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kBad),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await VideoToolkit.cancel();
    } catch (_) {
      // Nothing was running.
    }
    await widget.store.clear();
    await _loadStorage();
    if (mounted) _toast('Saved runs deleted.');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
          children: [
            const SectionLabel('Gateway key'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        widget.prefs.usingAnonymous
                            ? Icons.public_rounded
                            : Icons.vpn_key_rounded,
                        size: 17,
                        color: widget.prefs.usingAnonymous ? kAccent : kGood,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.prefs.usingAnonymous
                            ? 'Free anonymous tier'
                            : 'Your own key',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _key,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'API key',
                      hintText: 'Leave empty for the free tier',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 19,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _saveKey,
                          child: const Text('Save key'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _useFreeTier,
                          child: const Text('Use free tier'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'The key is stored only on this phone. With no key, the app '
                    'uses the gateway\'s anonymous tier.',
                    style: TextStyle(color: kMuted, fontSize: 11.5, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionLabel('Free tier limits'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fact(Icons.speed_rounded, PipelineConfig.anonymousLimits),
                  const SizedBox(height: 10),
                  _fact(
                    Icons.timer_outlined,
                    'Up to 900 frames per clip — the app trims to '
                    '${PipelineConfig.maxClipSeconds.round()} s at 30 fps.',
                  ),
                  const SizedBox(height: 10),
                  _fact(
                    Icons.wifi_rounded,
                    'Limits apply per public IP, so a whole gym on one Wi-Fi '
                    'shares them. Your own key avoids that.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionLabel('On this phone'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _loading
                              ? 'Measuring…'
                              : '$_runs ${_runs == 1 ? 'run' : 'runs'} · '
                                  '${fmtBytes(_bytes)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: _runs == 0 ? null : _clearHistory,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kBad,
                          side: BorderSide(
                            color: _runs == 0
                                ? kLine
                                : kBad.withValues(alpha: 0.5),
                          ),
                          minimumSize: const Size(0, 42),
                        ),
                        child: const Text('Delete all'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Each run keeps its trimmed clip, the pose reply and the '
                    'analysis. Reopening one costs no network.',
                    style: TextStyle(color: kMuted, fontSize: 11.5, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionLabel('About'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fact(
                    Icons.accessibility_new_rounded,
                    'Poses from ${PipelineConfig.poseModel} through the VLM Run '
                    'gateway.',
                  ),
                  const SizedBox(height: 10),
                  _fact(
                    Icons.lock_outline_rounded,
                    'Your original video never leaves the phone — only the '
                    'trimmed 720p copy is uploaded for pose estimation.',
                  ),
                  const SizedBox(height: 10),
                  _fact(
                    Icons.info_outline_rounded,
                    'Pull-Up Coach · Android · 1.0.0',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fact(IconData icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Icon(icon, size: 15, color: kMuted),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(color: kMuted, fontSize: 12, height: 1.4),
        ),
      ),
    ],
  );
}
