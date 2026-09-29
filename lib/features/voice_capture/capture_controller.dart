/// Mesin keadaan alur perekaman.
///
/// Perhatikan bahwa tidak ada satu pun keadaan yang menuju penyimpanan.
/// Keadaan paling akhir yang bisa dicapai alur ini adalah [CaptureReady], yang
/// berarti "draft siap ditinjau manusia". Penyimpanan hanya terjadi setelah
/// layar konfirmasi memanggil confirmDraftByUser.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/confidence.dart';
import '../transactions/domain/transaction_draft.dart';
import 'speech_service.dart';

sealed class CaptureState {
  const CaptureState();
}

class CaptureIdle extends CaptureState {
  const CaptureIdle();
}

class CaptureInProgress extends CaptureState {
  final String partialText;
  final SpeechEngineKind? engine;

  const CaptureInProgress({this.partialText = '', this.engine});
}

class CaptureProcessing extends CaptureState {
  final String transcript;
  const CaptureProcessing(this.transcript);
}

class CaptureReady extends CaptureState {
  final TransactionDraft draft;
  const CaptureReady(this.draft);
}

/// Suara tidak bisa dipakai. UI wajib menawarkan masukan manual di sini,
/// bukan sekadar memunculkan pesan galat.
class CaptureUnavailable extends CaptureState {
  final VoiceUnavailableReason reason;
  const CaptureUnavailable(this.reason);
}

class CaptureController extends Notifier<CaptureState> {
  StreamSubscription<CaptureEvent>? _subscription;
  String _latestTranscript = '';
  Confidence _latestConfidence = const Confidence.unknown();

  int _session = 0;
  bool _disposed = false;

  bool _isCurrent(int session) => !_disposed && session == _session;

  @override
  CaptureState build() {
    final speech = ref.read(speechServiceProvider);
    ref.onDispose(() {
      _disposed = true;
      _session++;
      unawaited(_subscription?.cancel());
      unawaited(speech.cancel());
    });
    return const CaptureIdle();
  }

  Future<void> start() async {
    if (state is CaptureInProgress || state is CaptureProcessing) return;
    final session = ++_session;
    state = const CaptureInProgress();
    _latestTranscript = '';
    _latestConfidence = const Confidence.unknown();
    try {
      await _subscription?.cancel();
      if (!_isCurrent(session)) return;
      _subscription = ref
          .read(speechServiceProvider)
          .listen()
          .listen(
            (event) {
              if (_isCurrent(session) && state is CaptureInProgress) {
                _onEvent(event);
              }
            },
            onError: (_) {
              if (_isCurrent(session) && state is CaptureInProgress) {
                state = const CaptureUnavailable(
                  VoiceUnavailableReason.recognitionError,
                );
              }
            },
            onDone: () {
              if (_isCurrent(session) && state is CaptureInProgress) {
                unawaited(_finish());
              }
            },
          );
    } catch (_) {
      if (_isCurrent(session)) {
        state = const CaptureUnavailable(
          VoiceUnavailableReason.recognitionError,
        );
      }
    }
  }

  void _onEvent(CaptureEvent event) {
    switch (event) {
      case CaptureListening(:final engine):
        state = CaptureInProgress(
          partialText: _latestTranscript,
          engine: engine,
        );
      case CaptureTranscript(:final result):
        _latestTranscript = result.text;
        _latestConfidence = result.confidence;
        if (result.isFinal) {
          unawaited(_finish());
        } else {
          final current = state;
          state = CaptureInProgress(
            partialText: result.text,
            engine: current is CaptureInProgress ? current.engine : null,
          );
        }
      case CaptureFailed(:final reason):
        state = CaptureUnavailable(reason);
    }
  }

  Future<void> _finish() async {
    // Hasil final, tombol stop, dan penutupan stream bisa datang bersamaan.
    if (state is! CaptureInProgress) return;
    final session = _session;
    final transcript = _latestTranscript.trim();
    final confidence = _latestConfidence;
    if (transcript.isEmpty) {
      state = const CaptureUnavailable(VoiceUnavailableReason.noSpeechDetected);
      return;
    }
    state = CaptureProcessing(transcript);
    try {
      final speech = ref.read(speechServiceProvider);
      final pipeline = ref.read(parserPipelineProvider);
      await speech.stop();
      if (!_isCurrent(session)) return;
      final result = await pipeline.parse(
        transcript,
        sttConfidence: confidence,
      );
      if (_isCurrent(session)) {
        state = CaptureReady(TransactionDraft.fromParseResult(result));
      }
    } catch (_) {
      if (_isCurrent(session)) {
        state = const CaptureUnavailable(
          VoiceUnavailableReason.recognitionError,
        );
      }
    }
  }

  Future<void> stop() async {
    if (state is! CaptureInProgress) return;
    final session = _session;
    try {
      await ref.read(speechServiceProvider).stop();
      if (_isCurrent(session)) await _finish();
    } catch (_) {
      if (_isCurrent(session) && state is CaptureInProgress) {
        state = const CaptureUnavailable(
          VoiceUnavailableReason.recognitionError,
        );
      }
    }
  }

  Future<void> cancel() async {
    final session = ++_session;
    final speech = ref.read(speechServiceProvider);
    state = const CaptureIdle();
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    if (_isCurrent(session)) await speech.cancel();
  }

  void reset() {
    // Hasil parser dari sesi sebelumnya tidak boleh membuka draf kembali.
    _session++;
    _latestTranscript = '';
    _latestConfidence = const Confidence.unknown();
    state = const CaptureIdle();
  }
}

final captureControllerProvider =
    NotifierProvider<CaptureController, CaptureState>(CaptureController.new);
