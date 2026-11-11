// Main menu: mode, colour, bot strength, start / continue.

import 'package:flutter/material.dart';

import '../chess/elo.dart';
import '../game/game_controller.dart';
import '../game/settings.dart';
import 'theme.dart';

/// Clock presets: (minutes per player, seconds added after every move). 0 minutes = no clock.
const List<(int, int)> clockPresets = [(0, 0), (1, 0), (3, 0), (3, 2), (5, 0), (10, 0), (15, 10), (30, 0)];

String clockLabel(int min, int inc) => min == 0 ? 'Off' : (inc > 0 ? '$min min + ${inc}s' : '$min min');

const List<int> eloPresets = [400, 800, 1200, 1600, 2000, 2400, 2800, 3200];

class MenuScreen extends StatelessWidget {
  const MenuScreen({
    super.key,
    required this.settings,
    required this.onSettings,
    required this.saved,
    required this.hasActive,
    required this.onStart,
    required this.onContinue,
    required this.onResumeSaved,
    required this.onOpenSettings,
    required this.onHost,
    required this.onJoin,
  });

  final Settings settings;
  final ValueChanged<Settings> onSettings;
  final SavedGame? saved;
  final bool hasActive;
  final void Function(Settings settings) onStart;
  final VoidCallback onContinue;
  final VoidCallback onResumeSaved;
  final VoidCallback onOpenSettings;
  final VoidCallback onHost;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final bot = settings.mode == GameMode.bot;
    final lan = settings.mode == GameMode.lan;
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(center: Alignment(0, -0.4), radius: 1.1, colors: [Color(0x5914100D), Color(0xCC0A0806)]),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: C.panel,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: C.line),
                  boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 60, offset: Offset(0, 20))],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset('assets/icon/icon.png', width: 64, height: 64),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('3D Chess', style: TextStyle(fontSize: 28, color: C.gold2, letterSpacing: 0.3)),
                        Text('Staunton set · works offline', style: TextStyle(color: C.muted, fontSize: 13)),
                      ]),
                    ),
                    GlassIconButton(icon: '⚙', tooltip: 'Settings', onPressed: onOpenSettings),
                  ]),
                  const SizedBox(height: 16),
                  _Seg(
                    key: const Key('mode-seg'),
                    items: const [
                      ('\u{1F916} Play the bot', GameMode.bot),
                      ('\u{1F465} 2 players\n1 phone', GameMode.local),
                      ('\u{1F4E1} 2 players\n2 phones', GameMode.lan),
                    ],
                    value: settings.mode,
                    onChanged: (m) => onSettings(settings.copyWith(mode: m)),
                  ),
                  const SizedBox(height: 16),
                  if (bot) ...[
                    const _Heading('Your colour'),
                    const SizedBox(height: 8),
                    _Seg(
                      key: const Key('color-seg'),
                      small: true,
                      items: const [
                        ('♔ White', HumanColor.white),
                        ('\u{1F3B2} Random', HumanColor.random),
                        ('♚ Black', HumanColor.black),
                      ],
                      value: settings.humanColor,
                      onChanged: (c) => onSettings(settings.copyWith(humanColor: c)),
                    ),
                    const SizedBox(height: 16),
                    Row(children: [
                      const Expanded(child: _Heading('Bot strength')),
                      Text('${settings.elo} Elo', key: const Key('elo-label'), style: const TextStyle(color: C.gold2, fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(eloName(settings.elo), overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 13)),
                      ),
                    ]),
                    Slider(
                      key: const Key('elo-slider'),
                      min: eloMin.toDouble(),
                      max: eloMax.toDouble(),
                      divisions: (eloMax - eloMin) ~/ 50,
                      value: settings.elo.clamp(eloMin, eloMax).toDouble(),
                      onChanged: (v) => onSettings(settings.copyWith(elo: v.round())),
                    ),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final e in eloPresets)
                        InkWell(
                          key: Key('elo-$e'),
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => onSettings(settings.copyWith(elo: e)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: (settings.elo - e).abs() < 25 ? C.gold : C.line),
                            ),
                            child: Text('$e', style: TextStyle(fontSize: 13, color: (settings.elo - e).abs() < 25 ? C.gold2 : C.muted)),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 8),
                    const Text('Stockfish runs on your device. Elo is approximate.', style: TextStyle(color: C.muted, fontSize: 12.5)),
                  ] else if (lan)
                    const Text(
                      'Each player uses their own phone. One phone hosts, the other searches for it and joins — no code, no internet needed, just the same Wi-Fi or one phone\'s mobile hotspot.',
                      key: Key('lan-hint'),
                      style: TextStyle(color: C.muted, fontSize: 14, height: 1.4),
                    )
                  else
                    const Text(
                      'Pass the phone or tablet back and forth — no internet needed. Turn on “Auto-flip board” in settings to turn the view 180° to the player whose turn it is.',
                      style: TextStyle(color: C.muted, fontSize: 14, height: 1.4),
                    ),
                  const SizedBox(height: 16),
                  _ClockPicker(settings: settings, onSettings: onSettings),
                  const SizedBox(height: 16),
                  if (lan) ...[
                    GoldButton(key: const Key('lan-host'), label: '\u{1F4E1} Host a game', onPressed: onHost),
                    const SizedBox(height: 10),
                    GhostButton(key: const Key('lan-join'), label: '\u{1F50D} Join a game', onPressed: onJoin),
                  ] else
                    GoldButton(key: const Key('start'), label: '▶ Start new game', onPressed: () => onStart(settings)),
                  if (!hasActive && saved != null) ...[
                    const SizedBox(height: 10),
                    GhostButton(
                      key: const Key('resume-saved'),
                      label: '↺ Continue saved game (${saved!.config.mode == GameMode.bot ? 'bot ${saved!.config.elo}' : '2 players'})',
                      onPressed: onResumeSaved,
                    ),
                  ],
                  if (hasActive) ...[
                    const SizedBox(height: 10),
                    GhostButton(key: const Key('continue'), label: '↺ Back to current game', onPressed: onContinue),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClockPicker extends StatelessWidget {
  const _ClockPicker({required this.settings, required this.onSettings});
  final Settings settings;
  final ValueChanged<Settings> onSettings;

  @override
  Widget build(BuildContext context) {
    final cur = (settings.timeMin, settings.incSec);
    final isPreset = clockPresets.contains(cur);
    Widget chip(Key key, String label, bool on, VoidCallback tap) => InkWell(
          key: key,
          borderRadius: BorderRadius.circular(999),
          onTap: tap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: on ? const Color(0x33F2C977) : null,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: on ? C.gold : C.line),
            ),
            child: Text(label, style: TextStyle(fontSize: 13, color: on ? C.gold2 : C.muted)),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Expanded(child: _Heading('Clock (optional)')),
        Text(clockLabel(settings.timeMin, settings.incSec), key: const Key('clock-label'), style: const TextStyle(color: C.gold2, fontSize: 14, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (min, inc) in clockPresets)
          chip(Key('clock-$min-$inc'), clockLabel(min, inc), cur == (min, inc), () => onSettings(settings.copyWith(timeMin: min, incSec: inc))),
        chip(
          const Key('clock-custom'),
          isPreset ? 'Custom…' : 'Custom: ${clockLabel(settings.timeMin, settings.incSec)}',
          !isPreset,
          () async {
            final r = await showDialog<(int, int)>(context: context, builder: (_) => _ClockDialog(min: settings.timeMin == 0 ? 5 : settings.timeMin, inc: settings.incSec));
            if (r != null) onSettings(settings.copyWith(timeMin: r.$1, incSec: r.$2));
          },
        ),
      ]),
      if (settings.timeMin > 0) ...[
        const SizedBox(height: 6),
        const Text('Each player gets this time. The clock starts after the first move; whoever runs out of time loses.', style: TextStyle(color: C.muted, fontSize: 12.5)),
      ],
    ]);
  }
}

class _ClockDialog extends StatefulWidget {
  const _ClockDialog({required this.min, required this.inc});
  final int min, inc;
  @override
  State<_ClockDialog> createState() => _ClockDialogState();
}

class _ClockDialogState extends State<_ClockDialog> {
  late final TextEditingController _min = TextEditingController(text: '${widget.min}');
  late final TextEditingController _inc = TextEditingController(text: '${widget.inc}');

  @override
  void dispose() {
    _min.dispose();
    _inc.dispose();
    super.dispose();
  }

  void _ok() {
    final m = (int.tryParse(_min.text.trim()) ?? 5).clamp(1, 180);
    final i = (int.tryParse(_inc.text.trim()) ?? 0).clamp(0, 60);
    Navigator.of(context).pop((m, i));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: C.panel,
        title: const Text('Custom clock', style: TextStyle(color: C.gold2)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            key: const Key('clock-min'),
            controller: _min,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Minutes per player (1–180)'),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('clock-inc'),
            controller: _inc,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Seconds added per move (0–60)'),
          ),
        ]),
        actions: [
          TextButton(key: const Key('clock-cancel'), onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(key: const Key('clock-ok'), onPressed: _ok, child: const Text('OK')),
        ],
      );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: const TextStyle(fontSize: 13, letterSpacing: 1, color: C.muted, fontWeight: FontWeight.w600));
}

class _Seg<T> extends StatelessWidget {
  const _Seg({super.key, required this.items, required this.value, required this.onChanged, this.small = false});
  final List<(String, T)> items;
  final T value;
  final ValueChanged<T> onChanged;
  final bool small;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: const Color(0xFF17110E),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF70583E)),
    ),
    child: Row(children: [
      for (final (label, v) in items)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onChanged(v),
                borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: EdgeInsets.symmetric(vertical: small ? 11 : 13, horizontal: 3),
                  decoration: BoxDecoration(
                    color: v == value ? const Color(0xFFF2C977) : const Color(0xFF30251E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: v == value ? const Color(0xFFFFE4A6) : const Color(0xFF594536),
                      width: v == value ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: small ? 13 : 14,
                      fontWeight: FontWeight.w800,
                      color: v == value ? const Color(0xFF201307) : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ]),
  );
}
