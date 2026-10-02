import 'package:flutter/widgets.dart';

import 'session_controller.dart';

class SessionScope extends InheritedNotifier<SessionController> {
  const SessionScope({
    required SessionController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static SessionController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SessionScope>();
    assert(scope != null, 'SessionScope is missing above this context.');
    return scope!.notifier!;
  }

  static SessionController read(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<SessionScope>();
    final scope = element?.widget as SessionScope?;
    assert(scope != null, 'SessionScope is missing above this context.');
    return scope!.notifier!;
  }
}
