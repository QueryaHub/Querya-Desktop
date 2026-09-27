import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Like [Offstage], but skips laying out the hidden child again while it
/// stays hidden, even if the incoming constraints keep changing (#984).
///
/// [RenderOffstage] still calls `child.layout(constraints)` on every frame
/// while offstage, so an animation that changes a sibling's size (e.g. the
/// sidebar-toggle spring resizing the workspace's [Expanded]) forces a full
/// layout pass through every hidden [QueryaSwitchingBody] layer each frame,
/// even though none of that layout is ever painted. [LazyOffstage] instead
/// reuses the child's last known size while hidden, and lays it out for real
/// exactly once when it becomes visible again (with the then-current
/// constraints, which may have changed while it was hidden).
class LazyOffstage extends SingleChildRenderObjectWidget {
  const LazyOffstage({super.key, this.offstage = true, super.child});

  final bool offstage;

  @override
  RenderLazyOffstage createRenderObject(BuildContext context) =>
      RenderLazyOffstage(offstage: offstage);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLazyOffstage renderObject,
  ) {
    renderObject.offstage = offstage;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<bool>('offstage', offstage));
  }

  @override
  SingleChildRenderObjectElement createElement() => _LazyOffstageElement(this);
}

class _LazyOffstageElement extends SingleChildRenderObjectElement {
  _LazyOffstageElement(LazyOffstage super.widget);

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    if (!(widget as LazyOffstage).offstage) {
      super.debugVisitOnstageChildren(visitor);
    }
  }
}

class RenderLazyOffstage extends RenderOffstage {
  RenderLazyOffstage({super.offstage, super.child});

  @override
  void performLayout() {
    if (offstage) {
      final child = this.child;
      // A child that has already been laid out at least once keeps its
      // last known size while hidden, instead of being re-laid-out with
      // whatever constraints happen to arrive this frame. `offstage`'s own
      // setter (in RenderOffstage) already forces a real layout the moment
      // this flips back to false, so the child is never shown with a stale
      // size for constraints that changed while it was hidden.
      if (child != null && child.hasSize) {
        return;
      }
      child?.layout(constraints);
      return;
    }
    super.performLayout();
  }
}
