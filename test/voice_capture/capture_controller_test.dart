import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_toko/app/providers.dart';
import 'package:smart_toko/core/confidence.dart';
import 'package:smart_toko/features/voice_capture/capture_controller.dart';
import 'package:smart_toko/features/voice_capture/speech_service.dart';
import 'package:smart_toko/features/voice_parser/domain/parse_result.dart';
import 'package:smart_toko/features/voice_parser/llm/llm_parser.dart';
import 'package:smart_toko/features/voice_parser/logging/parse_failure_logger.dart';
import 'package:smart_toko/features/voice_parser/parser_pipeline.dart';
import 'package:smart_toko/features/voice_parser/rules/rule_parser.dart';

class FakeSpeech extends SpeechService {
  final events = StreamController<CaptureEvent>();
  int starts = 0;
  bool failStop = false;

  @override
  Stream<CaptureEvent> listen({bool preferOnDevice = true}) {
    starts++;
    return events.stream;
  }

  @override
  Future<void> stop() async {
    if (failStop) throw StateError('stop failed');
    if (!events.isClosed) unawaited(events.close());
  }

  @override
  Future<void> cancel() async {
    if (!events.isClosed) unawaited(events.close());
  }

  @override
  Future<SpeechCapability> probe() async =>
      const SpeechReady(onDeviceAvailable: true, cloudAvailable: true);

  void transcript({bool finalResult = true}) => events.add(
    CaptureTranscript(
      TranscriptResult(
        text: 'jual indomie dua bungkus lima ribu',
        confidence: const Confidence(1),
        engine: SpeechEngineKind.onDevice,
        isFinal: finalResult,
      ),
    ),
  );
}

class DelayedParser extends ParserPipeline {
  final result = Completer<ParseResult>();
  int calls = 0;

  DelayedParser()
    : super(
        llmParser: const DisabledLlmParser(),
        failureLogger: InMemoryParseFailureLogger(),
        isOnline: () async => false,
      );

  @override
  Future<ParseResult> parse(
    String transcript, {
    Confidence sttConfidence = const Confidence(1),
  }) {
    calls++;
    return result.future;
  }

  void complete() => result.complete(
    const RuleBasedParser().parse('jual indomie dua bungkus lima ribu'),
  );
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeSpeech speech;
  late DelayedParser parser;
  late ProviderContainer container;
  late CaptureController controller;

  setUp(() {
    speech = FakeSpeech();
    parser = DelayedParser();
    container = ProviderContainer(
      overrides: [
        speechServiceProvider.overrideWithValue(speech),
        parserPipelineProvider.overrideWithValue(parser),
      ],
    );
    controller = container.read(captureControllerProvider.notifier);
  });
  tearDown(() => container.dispose());

  test('double start only opens one microphone session', () async {
    await Future.wait([controller.start(), controller.start()]);
    expect(speech.starts, 1);
  });

  test('final transcript and stop parse once', () async {
    await controller.start();
    speech.transcript();
    await flush();
    await controller.stop();
    expect(parser.calls, 1);
    parser.complete();
    await flush();
    expect(container.read(captureControllerProvider), isA<CaptureReady>());
  });

  test(
    'stream ending with partial transcript still opens confirmation',
    () async {
      await controller.start();
      speech.transcript(finalResult: false);
      await speech.events.close();
      await flush();
      expect(parser.calls, 1);
      parser.complete();
      await flush();
      expect(container.read(captureControllerProvider), isA<CaptureReady>());
    },
  );

  test('stop without speech offers manual entry', () async {
    await controller.start();
    await controller.stop();
    await flush();
    final state =
        container.read(captureControllerProvider) as CaptureUnavailable;
    expect(state.reason, VoiceUnavailableReason.noSpeechDetected);
    expect(parser.calls, 0);
  });

  test('cancel discards a parser result that arrives late', () async {
    await controller.start();
    speech.transcript();
    await flush();
    expect(parser.calls, 1);
    await controller.cancel();
    parser.complete();
    await flush();
    expect(container.read(captureControllerProvider), isA<CaptureIdle>());
  });

  test('reset discards a parser result that arrives late', () async {
    await controller.start();
    speech.transcript();
    await flush();
    controller.reset();
    parser.complete();
    await flush();
    expect(container.read(captureControllerProvider), isA<CaptureIdle>());
  });

  test('parser failure offers manual entry', () async {
    await controller.start();
    speech.transcript();
    await flush();
    parser.result.completeError(StateError('parser failed'));
    await flush();
    expect(
      container.read(captureControllerProvider),
      isA<CaptureUnavailable>(),
    );
  });

  test('stop failure offers manual entry', () async {
    await controller.start();
    speech.failStop = true;
    await controller.stop();
    expect(
      container.read(captureControllerProvider),
      isA<CaptureUnavailable>(),
    );
  });
}
