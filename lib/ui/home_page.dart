/// The start screen: choose the lift, bring in a clip, reopen a past run.
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/config.dart';
import '../core/prefs.dart';
import '../core/store.dart';
import '../core/video_toolkit.dart';
import '../main.dart' show routeObserver;
import 'format.dart';
import 'results_page.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'trim_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.prefs});

  final Prefs prefs;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with RouteAware {
  final RunStore _store = RunStore();
  final ImagePicker _picker = ImagePicker();

  late LiftMode _mode;
  List<RunMeta> _history = const [];
  bool _busy = false;
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    _mode = widget.prefs.mode;
    _refreshHistory();
    _recoverLostVideo();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    // A trim, analysis, result or settings screen just closed: history may
    // have changed underneath us.
    _refreshHistory();
  }

  Future<void> _refreshHistory() async {
    try {
      final history = await _store.history();
      if (!mounted) return;
      setState(() {
        _history = history;
        _loadingHistory = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
    }
  }

  /// Android may kill the app while the camera is open; hand the clip back.
  Future<void> _recoverLostVideo() async {
    try {
      final lost = await _picker.retrieveLostData();
      if (lost.isEmpty) return;
      final file = lost.file;
      if (file != null) await _openPath(file.path);
    } catch (_) {
      // Nothing was lost.
    }
  }

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final video = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 10),
      );
      if (video == null) return;
      await _openPath(video.path);
    } catch (error) {
      _toast(friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPath(String path) async {
    final info = await VideoToolkit.probe(path);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrimPage(
          path: path,
          info: info,
          mode: _mode,
          prefs: widget.prefs,
          store: _store,
        ),
      ),
    );
    await _refreshHistory();
  }

  Future<void> _openRun(RunMeta meta) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final run = await _store.load(meta.id);
      if (!mounted) return;
      if (run == null) {
        _toast('That run is missing its clip or poses.');
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ResultsPage(run: run)),
      );
    } catch (error) {
      _toast(friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteRun(RunMeta meta) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this run?'),
        content: Text(
          '${meta.title} from ${meta.subtitle.split(' · ').first} will be '
          'removed from this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kBad),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _store.delete(meta.id);
    await _refreshHistory();
  }

  Future<void> _setMode(LiftMode mode) async {
    if (mode == _mode) return;
    setState(() => _mode = mode);
    await widget.prefs.setMode(mode);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final anonymous = widget.prefs.usingAnonymous;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            _header(context),
            const SizedBox(height: 22),
            _modeSwitch(),
            const SizedBox(height: 22),
            _captureCard(),
            const SizedBox(height: 14),
            _tierNote(anonymous),
            const SizedBox(height: 30),
            _historyHeader(),
            const SizedBox(height: 12),
            if (_loadingHistory)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_history.isEmpty)
              _emptyHistory()
            else
              ..._history.map(
                (meta) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _historyTile(meta),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Row(
    children: [
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kAccent, kAccentDeep],
          ),
        ),
        child: const Icon(Icons.fitness_center, color: Color(0xFF04161C)),
      ),
      const SizedBox(width: 13),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pull-Up Coach',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Count reps, grade the range, watch it back',
              style: TextStyle(color: kMuted, fontSize: 12.5),
            ),
          ],
        ),
      ),
      IconButton(
        tooltip: 'Settings',
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SettingsPage(
                prefs: widget.prefs,
                store: _store,
              ),
            ),
          );
          if (!mounted) return;
          await _refreshHistory();
        },
        icon: const Icon(Icons.tune_rounded),
      ),
    ],
  );

  Widget _modeSwitch() {
    final modes = LiftMode.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kLine),
          ),
          child: Row(
            children: [
              for (final mode in modes)
                Expanded(
                  child: GestureDetector(
                    onTap: () => _setMode(mode),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(11),
                        color: mode == _mode ? kAccent : Colors.transparent,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            mode == LiftMode.pullUp
                                ? Icons.sports_gymnastics
                                : Icons.front_hand_rounded,
                            size: 17,
                            color: mode == _mode
                                ? const Color(0xFF04222A)
                                : kMuted,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            mode.label,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: mode == _mode
                                  ? const Color(0xFF04222A)
                                  : kText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        Text(
          _mode == LiftMode.pullUp
              ? 'Every pull counts. Each rep is graded full or partial range.'
              : 'A rep counts once the chin clears the bar. No range grading.',
          style: const TextStyle(color: kMuted, fontSize: 12.5, height: 1.35),
        ),
      ],
    );
  }

  Widget _captureCard() {
    final recorded = _mode == LiftMode.pullUp ? 'pull-ups' : 'chin-ups';
    return Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : () => _pick(ImageSource.camera),
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.videocam_rounded),
            label: const Text('Record a set'),
            style: FilledButton.styleFrom(
              backgroundColor: kAccent,
              foregroundColor: const Color(0xFF04222A),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _pick(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined, size: 19),
            label: const Text('Choose from gallery'),
          ),
          const SizedBox(height: 12),
          Text(
            'The system camera opens. Prop the phone side-on so your whole '
            'body and the bar stay in frame for the $recorded.',
            style: const TextStyle(color: kMuted, fontSize: 12.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _tierNote(bool anonymous) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: kSurfaceAlt.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kLine),
      ),
      child: Row(
        children: [
          Icon(
            anonymous ? Icons.public_rounded : Icons.vpn_key_rounded,
            size: 16,
            color: anonymous ? kAccent : kGood,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              anonymous
                  ? 'Free tier · ${PipelineConfig.anonymousLimits}. No account needed.'
                  : 'Using your own gateway key.',
              style: const TextStyle(color: kMuted, fontSize: 12, height: 1.35),
            ),
          ),
          TextButton(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsPage(
                    prefs: widget.prefs,
                    store: _store,
                  ),
                ),
              );
              if (mounted) setState(() {});
            },
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  Widget _historyHeader() => Row(
    children: [
      const Expanded(child: SectionLabel('Saved runs')),
      Text(
        _history.isEmpty ? '' : '${_history.length}',
        style: const TextStyle(
          color: kMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  Widget _emptyHistory() => Panel(
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kSurfaceAlt,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.history_rounded, color: kMuted, size: 26),
        ),
        const SizedBox(height: 12),
        const Text(
          'No runs yet',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 5),
        const Text(
          'Analyse a clip and it stays here, on your phone, so you can watch '
          'it back without using the network again.',
          textAlign: TextAlign.center,
          style: TextStyle(color: kMuted, fontSize: 12.5, height: 1.4),
        ),
      ],
    ),
  );

  Widget _historyTile(RunMeta meta) {
    final graded = meta.graded > 0;
    return Material(
      color: kSurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openRun(meta),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kLine),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kSurfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${meta.reps}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        height: 1,
                      ),
                    ),
                    const Text(
                      'reps',
                      style: TextStyle(
                        color: kMuted,
                        fontSize: 9,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.mode.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta.subtitle,
                      style: const TextStyle(color: kMuted, fontSize: 11.5),
                    ),
                    if (graded) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          _tinyDot(meta.full == meta.graded ? kGood : kWarn),
                          const SizedBox(width: 5),
                          Text(
                            '${meta.full}/${meta.graded} full ROM',
                            style: const TextStyle(
                              color: kMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20, color: kMuted),
                onSelected: (value) {
                  if (value == 'delete') _deleteRun(meta);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'delete', child: Text('Delete run')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tinyDot(Color color) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
