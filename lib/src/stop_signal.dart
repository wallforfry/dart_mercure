import 'dart:async';

/// A one-shot stop notification whose listeners can be removed.
///
/// A listener added with `Future.then` stays attached until the future
/// completes, so every wait that ends on its own would leave one behind on a
/// long-lived subscription.
final class StopSignal {
  final Set<void Function()> _listeners = {};
  bool _isStopped = false;

  /// Whether [stop] has been called.
  bool get isStopped => _isStopped;

  /// The number of listeners still attached.
  int get listenerCount => _listeners.length;

  /// Calls each listener still attached when its turn comes, once: one
  /// detached by an earlier listener is skipped. A listener that throws is
  /// reported to the current zone and does not prevent the others.
  void stop() {
    _isStopped = true;
    for (final listener in _listeners.toList()) {
      if (!_listeners.remove(listener)) continue;
      try {
        listener();
      } catch (error, stackTrace) {
        Zone.current.handleUncaughtError(error, stackTrace);
      }
    }
  }

  /// Calls [listener] on [stop], at once if already stopped, and returns a
  /// function that detaches it. Listeners are compared by identity, so pass a
  /// distinct closure or tear-off per registration.
  void Function() onStop(void Function() listener) {
    if (_isStopped) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}
