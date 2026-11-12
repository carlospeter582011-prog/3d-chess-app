// Two-phone lobby: one phone hosts, the other searches for hosted games on the same network and joins. No codes.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../chess/types.dart';
import '../game/settings.dart';
import '../net/lan.dart';
import 'menu.dart' show clockLabel;
import 'theme.dart';

/// Called when the game is ready.
typedef LanStart = void Function(LanSetup setup);

Side _sideOf(String? ch) => ch == 'b' ? Side.b : Side.w;

class LanLobby extends StatefulWidget {
  const LanLobby({super.key, required this.host, required this.services, required this.onStart, required this.onCancel, this.rnd, this.timeSec = 0, this.incSec = 0, this.playerName = ''});
  final bool host;
  final LanServices services;
  final LanStart onStart;
  final VoidCallback onCancel;
  final math.Random? rnd;

  /// Host only: the clock chosen in the menu, sent to the guest with the start message.
  final int timeSec, incSec;

  /// This player's name, shown to the other phone.
  final String playerName;

  @override
  State<LanLobby> createState() => _LanLobbyState();
}

class _LanLobbyState extends State<LanLobby> {
  // host
  LanHost? _host;
  LanGuest? _guest;
  StreamSubscription<LanGuest>? _guestSub;
  HumanColor _color = HumanColor.white;
  // join
  LanScanner? _scanner;
  StreamSubscription<List<LanAdvert>>? _scanSub;
  List<LanAdvert> _games = const [];
  bool _joining = false;
  RemoteLink? _link;
  StreamSubscription<Map<String, dynamic>>? _linkSub;
  String? _error;
  bool _handedOver = false;

  String get _me => widget.playerName.trim().isEmpty ? 'Player' : widget.playerName.trim();

  @override
  void initState() {
    super.initState();
    unawaited(_openLobby());
  }

  Future<void> _openLobby() async {
    bool allowed;
    try {
      allowed = await widget.services.requestPermission();
    } catch (_) {
      allowed = false;
    }
    if (!mounted) return;
    if (!allowed) {
      setState(() {
        _error = 'Allow local network access in Android settings to play on Wi-Fi.';
      });
      return;
    }
    await (widget.host ? _startHosting() : _startScanning());
  }

  Future<void> _startHosting() async {
    try {
      final h = widget.services.makeHost(widget.playerName.trim().isEmpty ? randomGameName(widget.rnd) : "${widget.playerName.trim()}'s game");
      _host = h;
      await h.start();
      if (!mounted) return;
      _guestSub = h.guests.listen(_onGuest);
      setState(() {});
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not start a game here. Check that Wi-Fi or the hotspot is on.');
    }
  }

  void _onGuest(LanGuest g) {
    if (!mounted) return;
    setState(() => _guest = g);
    unawaited(g.link.done.then((_) {
      if (mounted && !_handedOver && identical(_guest, g)) setState(() => _guest = null);
    }));
  }

  Future<void> _startScanning() async {
    try {
      final s = widget.services.makeScanner();
      _scanner = s;
      await s.start();
      if (!mounted) return;
      _scanSub = s.games.listen((g) {
        if (mounted) setState(() => _games = g);
      });
      setState(() => _games = s.current);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not search the network. Check that Wi-Fi is on.');
    }
  }

  void _begin() {
    final g = _guest;
    if (g == null) return;
    final hostSide = switch (_color) {
      HumanColor.white => Side.w,
      HumanColor.black => Side.b,
      HumanColor.random => (widget.rnd ?? math.Random()).nextBool() ? Side.w : Side.b,
    };
    // a secret only these two phones know, so the guest (and nobody else) can come back after a dropped connection
    final r = widget.rnd ?? math.Random();
    final sid = '${DateTime.now().microsecondsSinceEpoch}-${r.nextInt(1 << 30)}-${r.nextInt(1 << 30)}';
    g.link.send({'t': 'start', 'you': hostSide.other.ch, 'time': widget.timeSec, 'inc': widget.incSec, 'sid': sid, 'host': _me});
    _handedOver = true;
    final host = _host;
    widget.onStart(LanSetup(
      link: g.link,
      mySide: hostSide,
      isHost: true,
      timeSec: widget.timeSec,
      incSec: widget.incSec,
      myName: _me,
      oppName: g.name,
      reconnect: host == null ? null : HostReconnect(host, sid),
    ));
  }

  Future<void> _join(LanAdvert ad) async {
    if (_joining) return;
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final link = await widget.services.join(ad, _me);
      if (!mounted) {
        unawaited(link.close());
        return;
      }
      _link = link;
      _linkSub = link.messages.listen((m) {
        if (m['t'] == 'start' && !_handedOver) {
          _handedOver = true;
          unawaited(_scanner?.stop());
          final t = m['time'], i = m['inc'], sid = m['sid'], hostName = m['host'];
          widget.onStart(LanSetup(
            link: link,
            mySide: _sideOf(m['you'] as String?),
            isHost: false,
            timeSec: t is num ? t.round() : 0,
            incSec: i is num ? i.round() : 0,
            myName: _me,
            oppName: hostName is String && hostName.isNotEmpty ? hostName : ad.name,
            reconnect: sid is String ? GuestReconnect(ad: ad, sid: sid, name: _me) : null,
          ));
        } else if (m['t'] == 'bye') {
          _leftHost();
        }
      });
      unawaited(link.done.then((_) {
        if (!_handedOver) _leftHost();
      }));
    } on LanJoinException catch (e) {
      if (mounted) setState(() {
        _joining = false;
        _error = e.message;
      });
    } catch (_) {
      if (mounted) setState(() {
        _joining = false;
        _error = 'Could not join that game.';
      });
    }
  }

  void _leftHost() {
    if (!mounted) return;
    _linkSub?.cancel();
    _link = null;
    setState(() {
      _joining = false;
      _error = 'The host left the game.';
    });
  }

  void _cancel() {
    if (!_handedOver) {
      unawaited(_guest?.link.close());
      unawaited(_link?.close());
    }
    widget.onCancel();
  }

  @override
  void dispose() {
    _guestSub?.cancel();
    _scanSub?.cancel();
    _linkSub?.cancel();
    if (!_handedOver) unawaited(_host?.stop()); // after the start the running game owns the host
    unawaited(_scanner?.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xE60A0806),
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
                ),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(widget.host ? 'Host a game' : 'Join a game', key: const Key('lan-title'), style: const TextStyle(fontSize: 24, color: C.gold2)),
                  const SizedBox(height: 6),
                  const Text('Both phones must be on the same Wi-Fi, or one phone\'s mobile hotspot.', style: TextStyle(color: C.muted, fontSize: 13.5, height: 1.4)),
                  const SizedBox(height: 16),
                  if (_error == null || _host != null || _scanner != null)
                    ...(widget.host ? _hostBody() : _joinBody()),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, key: const Key('lan-error'), style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 14)),
                  ],
                  const SizedBox(height: 16),
                  GhostButton(key: const Key('lan-cancel'), label: 'Cancel', onPressed: _cancel),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _hostBody() {
    final g = _guest;
    if (g == null) {
      return [
        Row(children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.gold)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _host == null ? 'Starting…' : 'Waiting for the other phone to join “${_host!.name}”…',
              key: const Key('lan-waiting'),
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ]),
      ];
    }
    return [
      Text('${g.name} joined!', key: const Key('lan-joined'), style: const TextStyle(color: C.gold2, fontSize: 18)),
      const SizedBox(height: 14),
      const Text('YOUR COLOUR', style: TextStyle(fontSize: 13, letterSpacing: 1, color: C.muted, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Row(children: [
        for (final (label, c) in const [('♔ White', HumanColor.white), ('\u{1F3B2} Random', HumanColor.random), ('♚ Black', HumanColor.black)])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                key: Key('lan-color-${c.name}'),
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _color = c),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: c == _color ? const Color(0xFFF2C977) : const Color(0xFF30251E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c == _color ? const Color(0xFFFFE4A6) : const Color(0xFF594536)),
                  ),
                  child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c == _color ? const Color(0xFF201307) : Colors.white)),
                ),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 10),
      Text(
        widget.timeSec == 0 ? 'Clock: off' : 'Clock: ${clockLabel(widget.timeSec ~/ 60, widget.incSec)}',
        key: const Key('lan-clock'),
        style: const TextStyle(color: C.muted, fontSize: 13.5),
      ),
      const SizedBox(height: 16),
      GoldButton(key: const Key('lan-start'), label: '▶ Start game', onPressed: _begin),
    ];
  }

  List<Widget> _joinBody() {
    if (_joining) {
      return [
        Row(children: const [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.gold)),
          SizedBox(width: 12),
          Expanded(child: Text('Joined — waiting for the host to start the game…', key: Key('lan-wait-start'), style: TextStyle(color: Colors.white, fontSize: 15))),
        ]),
      ];
    }
    if (_games.isEmpty) {
      return [
        Row(children: const [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.gold)),
          SizedBox(width: 12),
          Expanded(child: Text('Searching for games on this network…', key: Key('lan-searching'), style: TextStyle(color: Colors.white, fontSize: 15))),
        ]),
      ];
    }
    return [
      for (final ad in _games)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: const Color(0xFF30251E),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              key: Key('lan-game-${ad.id}'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => _join(ad),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  const Text('♞', style: TextStyle(fontSize: 22, color: C.gold2)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(ad.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                      Text(ad.address, style: const TextStyle(color: C.muted, fontSize: 12.5)),
                    ]),
                  ),
                  const Text('Join', style: TextStyle(color: C.gold2, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          ),
        ),
    ];
  }
}
