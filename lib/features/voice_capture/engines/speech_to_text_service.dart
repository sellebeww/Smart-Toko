/// Implementasi [SpeechService] di atas paket speech_to_text.
library;

import 'dart:async';

import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../core/confidence.dart';
import '../../../core/connectivity/connectivity_service.dart';
import '../speech_service.dart';

/// Bahasa Indonesia. Bila model luring untuk locale ini belum diunduh di
/// perangkat, pengenalan luring akan gagal dan kita jatuh ke jalur daring atau
/// masukan manual.
const String indonesianLocaleId = 'id_ID';

class SpeechToTextService implements SpeechService {
  final SpeechToText _speech;
  final ConnectivityService connectivity;

  bool _initialized = false;
  StreamController<CaptureEvent>? _controller;

  SpeechToTextService({required this.connectivity, SpeechToText? speech})
    : _speech = speech ?? SpeechToText();

  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onError: (_) => _emitError(),
      onStatus: (status) {
        if (status == 'done') {
          final controller = _controller;
          if (controller != null && !controller.isClosed) {
            unawaited(controller.close());
          }
        }
      },
    );
    return _initialized;
  }

  @override
  Future<SpeechCapability> probe() async {
    final ok = await _ensureInitialized();
    if (!ok) {
      return const SpeechUnavailable(VoiceUnavailableReason.noSpeechEngine);
    }
    if (!await _speech.hasPermission) {
      return const SpeechUnavailable(VoiceUnavailableReason.permissionDenied);
    }

    final locales = await _speech.locales();
    final hasIndonesian = locales.any(
      (l) => l.localeId.replaceAll('-', '_').startsWith('id'),
    );
    if (!hasIndonesian) {
      return const SpeechUnavailable(
        VoiceUnavailableReason.languageModelMissing,
      );
    }

    return SpeechReady(
      // Ketersediaan model luring tidak bisa ditanyakan langsung lewat API
      // paket ini; satu-satunya cara tahu adalah mencoba. Jadi di sini
      // dianggap mungkin, dan kegagalannya ditangani saat listen.
      onDeviceAvailable: true,
      cloudAvailable: await connectivity.isOnline(),
    );
  }

  @override
  Stream<CaptureEvent> listen({bool preferOnDevice = true}) {
    final controller = StreamController<CaptureEvent>();
    _controller = controller;
    unawaited(_start(controller, preferOnDevice: preferOnDevice));
    controller.onCancel = () async {
      if (identical(_controller, controller)) {
        _controller = null;
        await _speech.cancel();
      }
    };
    return controller.stream;
  }

  Future<void> _start(
    StreamController<CaptureEvent> controller, {
    required bool preferOnDevice,
  }) async {
    try {
      await _startChecked(controller, preferOnDevice: preferOnDevice);
    } catch (_) {
      await _fail(controller, VoiceUnavailableReason.recognitionError);
    }
  }

  bool _isActive(StreamController<CaptureEvent> controller) =>
      identical(_controller, controller) && !controller.isClosed;

  Future<void> _startChecked(
    StreamController<CaptureEvent> controller, {
    required bool preferOnDevice,
  }) async {
    final capability = await probe();
    if (!_isActive(controller)) return;
    if (capability is SpeechUnavailable) {
      await _fail(controller, capability.reason);
      return;
    }

    final online = await connectivity.isOnline();
    if (!_isActive(controller)) return;

    if (preferOnDevice) {
      final started = await _attempt(controller, onDevice: true);
      if (started) return;

      // Luring gagal. Jalur daring hanya masuk akal bila memang ada koneksi;
      // kalau tidak, jangan membuat pengguna menunggu sia-sia — langsung
      // serahkan ke masukan manual.
      if (!online) {
        await _fail(
          controller,
          VoiceUnavailableReason.offlineAndNoOnDeviceModel,
        );
        return;
      }
    }

    if (!online) {
      await _fail(controller, VoiceUnavailableReason.offlineAndNoOnDeviceModel);
      return;
    }

    final started = await _attempt(controller, onDevice: false);
    if (!started) {
      await _fail(controller, VoiceUnavailableReason.recognitionError);
    }
  }

  /// Setiap await di [_start] memberi kesempatan pengguna menekan berhenti,
  /// yang menutup controller. Tanpa pengecekan ini, add() setelahnya
  /// melempar "Cannot add event after closing".
  Future<void> _fail(
    StreamController<CaptureEvent> controller,
    VoiceUnavailableReason reason,
  ) async {
    if (controller.isClosed) return;
    controller.add(CaptureFailed(reason));
    await controller.close();
  }

  Future<bool> _attempt(
    StreamController<CaptureEvent> controller, {
    required bool onDevice,
  }) async {
    if (!_isActive(controller)) return true;
    final engine = onDevice
        ? SpeechEngineKind.onDevice
        : SpeechEngineKind.cloud;
    try {
      await _speech.listen(
        onResult: (result) => _onResult(controller, result, engine),
        listenOptions: SpeechListenOptions(
          onDevice: onDevice,
          partialResults: true,
          cancelOnError: true,
          localeId: indonesianLocaleId,
          listenMode: ListenMode.dictation,
          pauseFor: const Duration(seconds: 3),
          listenFor: const Duration(seconds: 30),
        ),
      );
      if (_isActive(controller)) controller.add(CaptureListening(engine));
      return true;
    } catch (_) {
      return false;
    }
  }

  void _onResult(
    StreamController<CaptureEvent> controller,
    SpeechRecognitionResult result,
    SpeechEngineKind engine,
  ) {
    if (controller.isClosed) return;
    controller.add(
      CaptureTranscript(
        TranscriptResult(
          text: result.recognizedWords,
          confidence: _readConfidence(result),
          engine: engine,
          isFinal: result.finalResult,
        ),
      ),
    );
  }

  /// Paket ini memakai -1 sebagai penanda "confidence tidak tersedia", dan
  /// sebagian engine Android justru melaporkan 0.0 pada hasil final. Keduanya
  /// berarti "tidak diketahui", bukan "sangat tidak yakin" — kalau disamakan,
  /// seluruh field akan selalu tampil kosong di perangkat tersebut.
  static Confidence _readConfidence(SpeechRecognitionResult result) {
    if (!result.hasConfidenceRating) return const Confidence.unknown();
    final value = result.confidence;
    if (value <= 0) return const Confidence.unknown();
    return Confidence(value.clamp(0.0, 1.0).toDouble());
  }

  void _emitError() {
    final controller = _controller;
    if (controller == null || controller.isClosed) return;
    controller.add(
      const CaptureFailed(VoiceUnavailableReason.recognitionError),
    );
  }

  @override
  Future<void> stop() async {
    final controller = _controller;
    await _speech.stop();
    if (identical(_controller, controller)) _controller = null;
    if (controller != null && !controller.isClosed) await controller.close();
  }

  @override
  Future<void> cancel() async {
    final controller = _controller;
    _controller = null;
    await _speech.cancel();
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
  }
}
