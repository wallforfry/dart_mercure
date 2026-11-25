import 'dart:async';

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

  test('skips a listener detached by an earlier one during stop', () {
    final signal = StopSignal();
    var calls = 0;
    late final void Function() detachSecond;
    signal.onStop(() => detachSecond());
    detachSecond = signal.onStop(() => calls++);

    signal.stop();

    expect(calls, 0);
  });

  test('calls the other listeners when one throws', () {
    final signal = StopSignal();
    final errors = <Object>[];
    var calls = 0;
    signal
      ..onStop(() => throw StateError('boom'))
      ..onStop(() => calls++);

    runZonedGuarded(signal.stop, (error, _) => errors.add(error));

    expect(calls, 1);
    expect(errors.single, isStateError);
  });

  test('keeps two equal tear-offs as separate listeners', () {
    final signal = StopSignal();
    final counter = _Counter();
    final detachFirst = signal.onStop(counter.increment);
    signal.onStop(counter.increment);

    detachFirst();
    signal.stop();

    expect(counter.calls, 1);
  });
}

final class _Counter {
  int calls = 0;

  void increment() => calls++;
}
