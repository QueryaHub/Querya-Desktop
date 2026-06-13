import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;

/// Notifies when a derived form-valid flag changes (avoids full-form [setState]).
class FormValidityNotifier {
  FormValidityNotifier(this._compute);

  final bool Function() _compute;
  final ValueNotifier<bool> listenable = ValueNotifier(false);

  bool get value => listenable.value;

  void listenTo(material.TextEditingController controller) {
    controller.addListener(_onChanged);
  }

  void unlistenFrom(material.TextEditingController controller) {
    controller.removeListener(_onChanged);
  }

  void _onChanged() {
    final next = _compute();
    if (next != listenable.value) {
      listenable.value = next;
    }
  }

  void seed() => _onChanged();

  void dispose() {
    listenable.dispose();
  }
}
