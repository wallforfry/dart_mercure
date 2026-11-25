import 'package:dart_mercure/src/stop_signal.dart';
import 'package:test/test.dart';

void main() {
  test('calls each listener once on stop', () {
    final signal = StopSignal();
    var calls = 0;
    signal.onStop(() => calls++);

    signal
      ..stop()
      ..stop();

    expect(calls, 1);
    expect(signal.isStopped, isTrue);
    expect(signal.listenerCount, 0);
  });

  test('does not call a detached listener', () {
    final signal = StopSignal();
    var calls = 0;
    final detach = signal.onStop(() => calls++);

    detach();
    signal.stop();

    expect(calls, 0);
    expect(signal.listenerCount, 0);
  });

  test('calls a listener added after stop at once', () {
    final signal = StopSignal()..stop();
    var calls = 0;

    signal.onStop(() => calls++);

    expect(calls, 1);
    expect(signal.listenerCount, 0);
  });
}
