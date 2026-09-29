/// Kontrak pengenalan ucapan.
///
/// Dibuat sebagai antarmuka supaya seluruh alur — termasuk jalur "suara tidak
/// tersedia" — bisa diuji tanpa mikrofon.
library;

import '../../core/confidence.dart';

enum SpeechEngineKind { onDevice, cloud }

/// Alasan fitur suara tidak bisa dipakai.
///
/// Setiap nilai harus punya kalimat penjelasan sendiri di UI: pengguna yang
/// ditolak tanpa alasan akan menyimpulkan aplikasinya rusak.
enum VoiceUnavailableReason {
  permissionDenied,
  noSpeechEngine,
  languageModelMissing,
  offlineAndNoOnDeviceModel,
  recognitionError,
  noSpeechDetected,
}

sealed class SpeechCapability {
  const SpeechCapability();
}

class SpeechReady extends SpeechCapability {
  final bool onDeviceAvailable;
  final bool cloudAvailable;

  const SpeechReady({
    required this.onDeviceAvailable,
    required this.cloudAvailable,
  });
}

class SpeechUnavailable extends SpeechCapability {
  final VoiceUnavailableReason reason;
  const SpeechUnavailable(this.reason);
}

class TranscriptResult {
  final String text;
  final Confidence confidence;
  final SpeechEngineKind engine;
  final bool isFinal;

  const TranscriptResult({
    required this.text,
    required this.confidence,
    required this.engine,
    required this.isFinal,
  });
}

sealed class CaptureEvent {
  const CaptureEvent();
}

class CaptureListening extends CaptureEvent {
  final SpeechEngineKind engine;
  const CaptureListening(this.engine);
}

class CaptureTranscript extends CaptureEvent {
  final TranscriptResult result;
  const CaptureTranscript(this.result);
}

/// Jalur suara menyerah. Pemanggil WAJIB membuka masukan manual, bukan sekadar
/// menampilkan pesan galat — inilah yang membuat aplikasi tetap berguna di
/// perangkat tanpa model bahasa Indonesia luring.
class CaptureFailed extends CaptureEvent {
  final VoiceUnavailableReason reason;
  const CaptureFailed(this.reason);
}

abstract class SpeechService {
  Future<SpeechCapability> probe();

  Stream<CaptureEvent> listen({bool preferOnDevice = true});

  Future<void> stop();

  Future<void> cancel();
}
