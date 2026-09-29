/// Penjadwalan ulang percobaan sinkronisasi yang gagal.
library;

import 'dart:math';

class SyncBackoff {
  final Duration base;
  final Duration ceiling;
  final int maxAttempts;

  /// Sebaran acak ±rasio ini. Tanpa jitter, seluruh perangkat yang gagal pada
  /// saat yang sama akan mencoba lagi serentak dan menghantam server bersamaan.
  final double jitterRatio;

  final Random _random;

  SyncBackoff({
    this.base = const Duration(seconds: 5),
    this.ceiling = const Duration(hours: 6),
    this.maxAttempts = 10,
    this.jitterRatio = 0.2,
    Random? random,
  }) : _random = random ?? Random();

  /// [attempt] dihitung dari 0 untuk percobaan ulang pertama.
  Duration delayFor(int attempt) {
    final safeAttempt = attempt.clamp(0, 30);
    final multiplier = 1 << safeAttempt;
    final raw = base.inMilliseconds * multiplier;
    final capped = min(raw, ceiling.inMilliseconds);

    final jitterSpan = (capped * jitterRatio).round();
    final offset = jitterSpan == 0
        ? 0
        : _random.nextInt(jitterSpan * 2) - jitterSpan;
    final withJitter = max(0, capped + offset);

    return Duration(milliseconds: withJitter);
  }

  DateTime nextAttemptAt(DateTime now, int attempt) =>
      now.add(delayFor(attempt));

  /// Setelah ambang ini, antrean berhenti mencoba sendiri dan menunggu
  /// perintah ulang dari pengguna — bukan dibuang diam-diam.
  bool isExhausted(int attemptCount) => attemptCount >= maxAttempts;
}
