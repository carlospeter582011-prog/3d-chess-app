import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Pure show/no-show rules, kept separate from the SDK so they can be unit-tested.
class AdGate {
  AdGate({this.cooldown = const Duration(minutes: 2)});

  /// Minimum time between two full-screen ads, so ads never come back to back.
  final Duration cooldown;

  /// An App Open ad is only valid for 4 hours after it was loaded (Google's rule).
  static const Duration appOpenLifetime = Duration(hours: 4);

  DateTime? lastShown;

  /// True while any full-screen ad is on screen.
  bool showing = false;

  bool allows(DateTime now) => !showing && (lastShown == null || now.difference(lastShown!) > cooldown);

  void markShown(DateTime now) {
    showing = true;
    lastShown = now;
  }

  void markDismissed() => showing = false;

  static bool appOpenExpired(DateTime loadedAt, DateTime now) => now.difference(loadedAt) >= appOpenLifetime;
}

/// Google Mobile Ads with the official Google SAMPLE (test) ad units. Replace them with production IDs only when
/// they are provided; never click your own production ads.
///
/// * App Open: shown on a cold start and when returning from the background, but never while a game is in progress
///   ([canShowAppOpen]) and never on top of another full-screen ad.
/// * Interstitial: only after a game has ended ([onGameFinished]).
/// * Both are preloaded; load failures (offline, no fill) are ignored so chess stays fully playable offline.
class AdsService {
  AdsService({this.canShowAppOpen});

  static const appOpenTestId = 'ca-app-pub-3940256099942544/9257395921';
  static const interstitialTestId = 'ca-app-pub-3940256099942544/1033173712';

  /// Returns false while a game is being played, so an App Open ad never covers the board mid-game.
  final bool Function()? canShowAppOpen;

  final AdGate _gate = AdGate();
  AppOpenAd? _open;
  DateTime? _openLoadedAt;
  InterstitialAd? _interstitial;
  bool _initialized = false;
  bool _loadingOpen = false;
  bool _loadingInterstitial = false;
  bool _coldStart = true;
  bool _disposed = false;

  Future<void> initialize() async {
    try {
      await MobileAds.instance.initialize();
      if (_disposed) return;
      _initialized = true;
      _loadOpen();
      _loadInterstitial();
    } catch (_) {
      // Offline chess must always remain playable.
    }
  }

  bool get _openAllowed => canShowAppOpen?.call() ?? true;

  void _loadOpen() {
    if (!_initialized || _disposed || _loadingOpen || _open != null) return;
    _loadingOpen = true;
    AppOpenAd.load(
      adUnitId: appOpenTestId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingOpen = false;
          if (_disposed) {
            ad.dispose();
            return;
          }
          _open = ad;
          _openLoadedAt = DateTime.now();
          if (_coldStart) {
            _coldStart = false;
            _showOpen(); // the first App Open ad of this launch
          }
        },
        onAdFailedToLoad: (_) {
          _loadingOpen = false;
        },
      ),
    );
  }

  void _loadInterstitial() {
    if (!_initialized || _disposed || _loadingInterstitial || _interstitial != null) return;
    _loadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: interstitialTestId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingInterstitial = false;
          if (_disposed) {
            ad.dispose();
            return;
          }
          _interstitial = ad;
        },
        onAdFailedToLoad: (_) {
          _loadingInterstitial = false;
        },
      ),
    );
  }

  void _showOpen() {
    final ad = _open;
    final loadedAt = _openLoadedAt;
    if (ad == null || loadedAt == null) {
      _loadOpen();
      return;
    }
    final now = DateTime.now();
    if (AdGate.appOpenExpired(loadedAt, now)) {
      ad.dispose();
      _open = null;
      _loadOpen();
      return;
    }
    if (!_gate.allows(now) || !_openAllowed) return;
    _open = null;
    _gate.markShown(now);
    ad.fullScreenContentCallback = FullScreenContentCallback<AppOpenAd>(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _gate.markDismissed();
        _loadOpen();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _gate.markDismissed();
        _loadOpen();
      },
    );
    ad.show();
  }

  /// Call when the app returns to the foreground.
  void onResume() {
    _coldStart = false;
    if (_open == null) {
      _loadOpen();
      return;
    }
    _showOpen();
  }

  /// At most one ad per completed game, never during an active match.
  void onGameFinished() {
    final ad = _interstitial;
    final now = DateTime.now();
    if (ad == null || !_gate.allows(now)) {
      _loadInterstitial();
      return;
    }
    _interstitial = null;
    _gate.markShown(now);
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _gate.markDismissed();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _gate.markDismissed();
        _loadInterstitial();
      },
    );
    ad.show();
  }

  void dispose() {
    _disposed = true;
    _open?.dispose();
    _interstitial?.dispose();
    _open = null;
    _interstitial = null;
  }
}
