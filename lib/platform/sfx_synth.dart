// Synthesised sounds. Piece moves and captures use a small physical model of a wooden piece knocking on a wooden board
// (several damped resonances, a short "tap" transient and a low body "thock"); check and end are soft bell tones.
// The samples are generated in Dart, wrapped as 16-bit WAV and handed to Android's SoundPool. A recorded file dropped
// into assets/sfx/<name>.wav|ogg|mp3 replaces the synthesised sound of that name (see assets/sfx/README.md).

import 'dart:math' as math;
import 'dart:typed_data';

const int sampleRate = 44100;

/// One click: noise + sine with a fast decay, through a band-pass filter at 1.6x the pitch (Q 0.9).
Float64List _click(double freq, double dur, double gain, double noise, math.Random rnd) {
  final len = (sampleRate * dur).floor();
  final raw = Float64List(len);
  for (var i = 0; i < len; i++) {
    final env = math.exp(-i / (len * 0.18));
    raw[i] = ((rnd.nextDouble() * 2 - 1) * noise + math.sin(2 * math.pi * freq * i / sampleRate) * (1 - noise)) * env;
  }
  // RBJ band-pass, constant 0 dB peak gain (same as WebAudio's "bandpass")
  final w0 = 2 * math.pi * (freq * 1.6) / sampleRate;
  final alpha = math.sin(w0) / (2 * 0.9);
  final a0 = 1 + alpha;
  final b0 = alpha / a0, b2 = -alpha / a0;
  final a1 = -2 * math.cos(w0) / a0, a2 = (1 - alpha) / a0;
  final out = Float64List(len);
  var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
  for (var i = 0; i < len; i++) {
    final x = raw[i];
    final y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1;
    x1 = x;
    y2 = y1;
    y1 = y;
    out[i] = y * gain;
  }
  return out;
}

/// A wooden piece knocking on a wooden board. [bright] (0..1.2) is how hard / sharp the hit is.
Float64List _knock(double freq, double dur, double gain, double bright, math.Random rnd) {
  final len = (sampleRate * dur).floor();
  final out = Float64List(len);
  const ratios = [1.0, 2.32, 3.87, 5.41]; // inharmonic partials of a small block of wood
  const amps = [1.0, 0.55, 0.3, 0.16];
  const taus = [0.045, 0.028, 0.017, 0.010]; // seconds: higher partials die first
  final phase = [for (var k = 0; k < 4; k++) rnd.nextDouble() * 0.6];
  var lp = 0.0;
  for (var i = 0; i < len; i++) {
    final t = i / sampleRate;
    var v = 0.0;
    for (var k = 0; k < 4; k++) {
      v += amps[k] * (k == 0 ? 1.0 : bright) * math.exp(-t / taus[k]) * math.sin(2 * math.pi * freq * ratios[k] * t + phase[k]);
    }
    // low board "thock"
    v += 0.8 * math.exp(-t / 0.035) * math.sin(2 * math.pi * freq * 0.42 * t);
    // 3 ms tap transient: low-passed noise
    lp += 0.35 * ((rnd.nextDouble() * 2 - 1) - lp);
    v += 1.1 * bright * lp * math.exp(-t / 0.0014);
    final attack = math.min(1.0, t / 0.0003); // 0.3 ms ramp, no click
    out[i] = v * attack * gain * 0.55;
  }
  return out;
}

class _Part {
  final double freq, dur, gain, noise;
  final double offsetMs;

  /// True: wooden knock (noise = brightness); false: soft bell tone.
  final bool knock;
  const _Part(this.freq, this.dur, this.gain, this.noise, [this.offsetMs = 0, this.knock = false]);
}

/// Sound sets. 'wood' is the original wooden knock; 'glass' is bright and tonal; 'soft' is a muted low thud.
const Map<String, Map<String, List<_Part>>> _packs = {
  'wood': {
    'move': [_Part(470, 0.16, 0.95, 0.8, 0, true)],
    'capture': [_Part(340, 0.22, 1.15, 1.1, 0, true), _Part(520, 0.13, 0.7, 0.8, 58, true)],
    'check': [_Part(520, 0.18, 0.7, 0.2), _Part(690, 0.22, 0.6, 0.1, 110)],
    'end': [_Part(330, 0.3, 0.7, 0.1), _Part(247, 0.4, 0.7, 0.1, 180)],
  },
  'glass': {
    'move': [_Part(1450, 0.12, 0.85, 0.12)],
    'capture': [_Part(1100, 0.16, 1.0, 0.2), _Part(1650, 0.12, 0.6, 0.1, 45)],
    'check': [_Part(880, 0.25, 0.7, 0.05), _Part(1175, 0.3, 0.6, 0.05, 120)],
    'end': [_Part(660, 0.4, 0.7, 0.05), _Part(495, 0.5, 0.7, 0.05, 200)],
  },
  'soft': {
    'move': [_Part(250, 0.15, 0.7, 0.3, 0, true)],
    'capture': [_Part(200, 0.2, 0.9, 0.5, 0, true), _Part(300, 0.12, 0.5, 0.3, 50, true)],
    'check': [_Part(392, 0.25, 0.5, 0.05), _Part(523, 0.3, 0.45, 0.05, 130)],
    'end': [_Part(262, 0.4, 0.55, 0.05), _Part(196, 0.5, 0.55, 0.05, 220)],
  },
};

/// Names of the sound sets.
List<String> get soundPacks => _packs.keys.toList();

/// Names of all sounds.
List<String> get soundNames => _packs['wood']!.keys.toList();

/// Mono PCM samples in -1..1.
Float64List synthesize(String name, {int seed = 7, String pack = 'wood'}) {
  final parts = (_packs[pack] ?? _packs['wood']!)[name];
  if (parts == null) throw ArgumentError('unknown sound $name');
  final rnd = math.Random(seed);
  var total = 0;
  for (final p in parts) {
    total = math.max(total, (sampleRate * p.offsetMs / 1000).round() + (sampleRate * p.dur).floor());
  }
  final mix = Float64List(total);
  for (final p in parts) {
    final c = p.knock ? _knock(p.freq, p.dur, p.gain, p.noise, rnd) : _click(p.freq, p.dur, p.gain, p.noise, rnd);
    final off = (sampleRate * p.offsetMs / 1000).round();
    for (var i = 0; i < c.length; i++) {
      mix[off + i] += c[i];
    }
  }
  for (var i = 0; i < mix.length; i++) {
    mix[i] = (mix[i] * 1.2).clamp(-1.4, 1.4) / 1.4; // gentle ceiling, stays within -1..1
  }
  return mix;
}

/// A complete mono 16-bit WAV file.
Uint8List toWav(Float64List samples, {int rate = sampleRate}) {
  final dataLen = samples.length * 2;
  final b = ByteData(44 + dataLen);
  void str(int off, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(off + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  b.setUint32(4, 36 + dataLen, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  str(36, 'data');
  b.setUint32(40, dataLen, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    b.setInt16(44 + i * 2, (samples[i] * 32767 * 0.9).round().clamp(-32768, 32767), Endian.little);
  }
  return b.buffer.asUint8List();
}
