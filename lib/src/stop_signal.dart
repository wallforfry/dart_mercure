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

  /// Calls every attached listener once. Later calls find no listener left.
  void stop() {
    _isStopped = true;
    final listeners = _listeners.toList();
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  /// Calls [listener] on [stop], at once if already stopped, and returns a
  /// function that detaches it.
  void Function() onStop(void Function() listener) {
    if (_isStopped) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}
