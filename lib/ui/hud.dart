// In-game HUD: one slim row of buttons along the bottom (menu, settings and the game controls). A small chip row
// at the top shows the clocks and anything that needs attention (check, lost connection, requests). Nothing else.

import 'package:flutter/material.dart';

import '../chess/types.dart';
import '../game/game_controller.dart';
import '../game/settings.dart';
import '../scene/board_scene.dart';
import 'theme.dart';

/// The status line shown at the top.
({String text, String tone}) statusText(GameSnapshot s) {
  final bot = s.config.mode == GameMode.bot;
  final lan = s.config.mode == GameMode.lan;
  final human = s.config.humanColor;
  if (s.status != GameStatus.playing) {
    final w = s.winner?.label;
    final text = switch (s.status) {
      GameStatus.checkmate => 'Checkmate · $w wins',
      GameStatus.resigned => '${s.reason} · $w wins',
      _ => 'Draw · ${s.reason}',
    };
    return (text: text, tone: 'over');
  }
  if (lan && s.linkLost) return (text: '${s.opponentName} disconnected · waiting to reconnect…', tone: 'check');
  if (lan && s.drawOfferOut) return (text: 'Draw offered · waiting for the answer', tone: 'think');
  if (lan && s.takebackOut) return (text: 'Take-back requested · waiting for the answer', tone: 'think');
  if (lan && s.notice != null) return (text: s.notice!, tone: 'think');
  if (s.thinking) return (text: 'Bot is thinking…', tone: 'think');
  if (s.check) {
    return (text: (bot || lan) ? (s.turn == human ? 'Your king is in check!' : 'Check!') : '${s.turn.label} is in check!', tone: 'check');
  }
  if (bot) return (text: s.turn == human ? 'Your move' : '…', tone: '');
  if (lan) return (text: s.turn == human ? 'Your move' : '${s.opponentName} is thinking…', tone: '');
  return (text: '${s.turn.label} to move', tone: '');
}

/// "m:ss" (or "h:mm:ss"), rounding up so the clock never shows 0:00 before it has really run out.
String formatClock(int ms) {
  final t = (ms + 999) ~/ 1000;
  final h = t ~/ 3600, m = (t % 3600) ~/ 60, s = t % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

class _Clock extends StatelessWidget {
  const _Clock({required this.ms, required this.running, required this.side});
  final int ms;
  final bool running;
  final Side side;

  @override
  Widget build(BuildContext context) {
    final low = ms <= 20000;
    return Container(
      key: Key('clock-${side.ch}'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: running ? (low ? const Color(0xFF7A1F1A) : const Color(0xFF3A2D1E)) : const Color(0xFF17110E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: running ? C.gold : C.line),
      ),
      child: Text(
        formatClock(ms),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 16,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: low && ms > 0 ? const Color(0xFFFF8A80) : Colors.white,
        ),
      ),
    );
  }
}

class _CtrlButton extends StatelessWidget {
  const _CtrlButton({super.key, required this.icon, required this.label, required this.onPressed, this.on = false, this.compact = false});
  final String icon, label;
  final bool compact;
  final VoidCallback? onPressed;
  final bool on;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onPressed == null ? 0.4 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onPressed,
            child: Ink(
              height: compact ? 42 : 54,
              decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: on ? C.gold : C.line)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(icon, style: TextStyle(fontSize: compact ? 16 : 19, height: 1, color: on ? C.gold2 : C.text, fontWeight: FontWeight.bold)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: TextStyle(fontSize: compact ? 10 : 11, color: C.muted))),
                ),
              ]),
            ),
          ),
        ),
      );
}

enum ConfirmKind { resign, draw, rematch }

class Hud extends StatefulWidget {
  const Hud({
    super.key,
    required this.game,
    required this.snapshot,
    required this.board,
    required this.onMenu,
    required this.onSettings,
    this.wide = false,
  });

  final GameController game;
  final GameSnapshot snapshot;
  final BoardScene board;
  final VoidCallback onMenu, onSettings;
  final bool wide;

  @override
  State<Hud> createState() => _HudState();
}

class _HudState extends State<Hud> {
  bool topView = false;

  String _confirmTitle(ConfirmKind k) {
    final s = widget.snapshot;
    final bot = s.config.mode == GameMode.bot;
    final lan = s.config.mode == GameMode.lan;
    switch (k) {
      case ConfirmKind.resign:
        return (bot || lan) ? 'Resign?' : '${s.turn.label} resigns?';
      case ConfirmKind.draw:
        return lan ? 'Offer a draw to your opponent?' : 'Both players agree to a draw?';
      case ConfirmKind.rematch:
        return 'Start a rematch?';
    }
  }

  Future<void> _confirm(ConfirmKind k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: C.panelSolid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: C.line)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_confirmTitle(k), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: GhostButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop(false))),
              const SizedBox(width: 8),
              Expanded(child: GoldButton(key: const Key('confirm-yes'), label: 'Yes', onPressed: () => Navigator.of(ctx).pop(true))),
            ]),
          ]),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    switch (k) {
      case ConfirmKind.resign:
        widget.game.resign();
      case ConfirmKind.draw:
        if (widget.snapshot.config.mode == GameMode.lan) {
          widget.game.offerDraw();
        } else {
          widget.game.agreeDraw();
        }
      case ConfirmKind.rematch:
        if (widget.snapshot.config.mode == GameMode.lan) {
          widget.game.requestRematch();
        } else {
          widget.game.start(widget.snapshot.config);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.snapshot;
    final bot = s.config.mode == GameMode.bot;
    final lan = s.config.mode == GameMode.lan;
    final mine = bot || lan; // one human side on this phone
    final human = s.config.humanColor;
    final st = statusText(s);
    final over = s.status != GameStatus.playing;

    // Small chips: clocks (when timed) and a status only when there is something to say.
    final showStatus = lan || st.tone != '';
    final chips = <Widget>[
      if (s.config.timed) _Clock(ms: s.whiteMs, running: s.status == GameStatus.playing && s.turn == Side.w && s.history.isNotEmpty, side: Side.w),
      if (showStatus)
        Flexible(
          child: Container(
            key: const Key('status'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: switch (st.tone) { 'check' => const Color(0xE6A0281C), _ => C.panel },
              gradient: st.tone == 'over' ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.gold2, C.gold]) : null,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: st.tone == 'check' ? const Color(0x80FF7864) : (st.tone == 'over' ? Colors.transparent : C.line)),
            ),
            child: Text(
              st.text,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: switch (st.tone) { 'check' => Colors.white, 'over' => C.onGold, 'think' => C.gold2, _ => C.text },
              ),
            ),
          ),
        ),
      if (s.config.timed) _Clock(ms: s.blackMs, running: s.status == GameStatus.playing && s.turn == Side.b && s.history.isNotEmpty, side: Side.b),
    ];
    final info = chips.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < chips.length; i++) ...[if (i > 0) const SizedBox(width: 6), chips[i]],
            ]),
          );

    final buttons = <Widget>[
      _CtrlButton(compact: true, key: const Key('btn-menu'), icon: '☰', label: 'Menu', onPressed: widget.onMenu),
      _CtrlButton(compact: true, key: const Key('btn-settings'), icon: '⚙', label: 'Settings', onPressed: widget.onSettings),
      if (lan)
        _CtrlButton(compact: true, key: const Key('btn-undo'), icon: '↶', label: 'Take back', onPressed: s.canTakeback ? widget.game.requestTakeback : null)
      else
        _CtrlButton(compact: true, key: const Key('btn-undo'), icon: '↶', label: 'Undo', onPressed: s.canUndo ? widget.game.undo : null),
      _CtrlButton(compact: true, key: const Key('btn-flip'), icon: '⟳', label: 'Flip', onPressed: widget.board.flipView),
      _CtrlButton(
        compact: true,
        key: const Key('btn-top'),
        icon: '⬒',
        label: 'Top',
        on: topView,
        onPressed: () {
          final next = !topView;
          setState(() => topView = next);
          widget.board.resetCamera(animate: true, side: widget.board.viewSide(), top: next);
        },
      ),
      _CtrlButton(
        compact: true,
        key: const Key('btn-reset'),
        icon: '◎',
        label: 'Reset',
        onPressed: () {
          setState(() => topView = false);
          widget.board.resetCamera(animate: true, side: mine ? human : widget.board.viewSide());
        },
      ),
      if (over)
        _CtrlButton(
          compact: true,
          key: const Key('btn-rematch'),
          icon: '♻',
          label: s.rematchWaiting ? 'Waiting…' : 'Rematch',
          onPressed: (s.rematchWaiting || (lan && s.linkLost)) ? null : () => _confirm(ConfirmKind.rematch),
        )
      else if (bot)
        _CtrlButton(compact: true, key: const Key('btn-resign'), icon: '⚑', label: 'Resign', onPressed: () => _confirm(ConfirmKind.resign))
      else ...[
        _CtrlButton(compact: true, key: const Key('btn-draw'), icon: '½', label: 'Draw', onPressed: () => _confirm(ConfirmKind.draw)),
        _CtrlButton(compact: true, key: const Key('btn-resign'), icon: '⚑', label: 'Resign', onPressed: () => _confirm(ConfirmKind.resign)),
      ],
    ];

    final bar = Container(
      decoration: widget.wide
          ? const BoxDecoration(color: Color(0xFF17110D), border: Border(top: BorderSide(color: C.line)))
          : null,
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: Row(children: [for (final w in buttons) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: w))]),
    );

    // The empty middle lets touches reach the board.
    return Column(children: [
      SafeArea(bottom: false, child: info),
      const Spacer(),
      SafeArea(top: false, child: bar),
    ]);
  }
}
