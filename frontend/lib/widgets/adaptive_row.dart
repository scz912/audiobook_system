import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

enum AdaptiveRowSlot { leading, body, trailing }

/* A card's row - a [leading] picture, its [body] text and [trailing]
   buttons - that never squeezes its text.

   Laid out like a Row (body in the middle, taking the room that's left)
   while the body gets at least [minBodyWidth]. When the screen is too
   narrow for that (a small phone, the phone's text size turned up, a long
   translation on a button) the buttons move to their own line under the
   text, at the right, and the text gets the card's full width beside the
   picture:

       wide:    [pic] Name               [Enter] (e) (x)
                      Age 9 • Fantasy

       narrow:  [pic] Name
                      Age 9 • Fantasy
                                         [Enter] (e) (x)

   [minBodyWidth] grows with the phone's text size, so bigger text gives
   way to the buttons sooner. If the buttons could be wider than the whole
   card, make [trailing] a Wrap so they can break onto more lines.

   It never asks its children for their intrinsic sizes, so the body may
   hold a LayoutBuilder (WholeWordsText) and the like. */
class AdaptiveRow
    extends SlottedMultiChildRenderObjectWidget<AdaptiveRowSlot, RenderBox> {
  final Widget? leading;
  final Widget body;
  final Widget? trailing;
  // The narrowest the body may get (at normal text size) before the
  // trailing buttons move under it.
  final double minBodyWidth;
  // Between the leading picture and the body.
  final double gap;
  // Between the body and the trailing buttons, side by side.
  final double trailingGap;
  // Between the body and the trailing buttons when they're stacked.
  final double runGap;

  const AdaptiveRow({
    super.key,
    this.leading,
    required this.body,
    this.trailing,
    this.minBodyWidth = 140,
    this.gap = 14,
    this.trailingGap = 8,
    this.runGap = 10,
  });

  @override
  Iterable<AdaptiveRowSlot> get slots => AdaptiveRowSlot.values;

  @override
  Widget? childForSlot(AdaptiveRowSlot slot) => switch (slot) {
    AdaptiveRowSlot.leading => leading,
    AdaptiveRowSlot.body => body,
    AdaptiveRowSlot.trailing => trailing,
  };

  // The minimum body width at the phone's current text size.
  double _scaledMin(BuildContext context) =>
      minBodyWidth * MediaQuery.textScalerOf(context).scale(14) / 14;

  @override
  RenderAdaptiveRow createRenderObject(BuildContext context) =>
      RenderAdaptiveRow(
        minBodyWidth: _scaledMin(context),
        gap: gap,
        trailingGap: trailingGap,
        runGap: runGap,
      );

  @override
  void updateRenderObject(BuildContext context, RenderAdaptiveRow renderObject) {
    renderObject
      ..minBodyWidth = _scaledMin(context)
      ..gap = gap
      ..trailingGap = trailingGap
      ..runGap = runGap;
  }
}

class RenderAdaptiveRow extends RenderBox
    with SlottedContainerRenderObjectMixin<AdaptiveRowSlot, RenderBox> {
  RenderAdaptiveRow({
    required double minBodyWidth,
    required double gap,
    required double trailingGap,
    required double runGap,
  }) : _minBodyWidth = minBodyWidth,
       _gap = gap,
       _trailingGap = trailingGap,
       _runGap = runGap;

  double _minBodyWidth;
  set minBodyWidth(double v) {
    if (v == _minBodyWidth) return;
    _minBodyWidth = v;
    markNeedsLayout();
  }

  double _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  double _trailingGap;
  set trailingGap(double v) {
    if (v == _trailingGap) return;
    _trailingGap = v;
    markNeedsLayout();
  }

  double _runGap;
  set runGap(double v) {
    if (v == _runGap) return;
    _runGap = v;
    markNeedsLayout();
  }

  RenderBox? get _leading => childForSlot(AdaptiveRowSlot.leading);
  RenderBox? get _body => childForSlot(AdaptiveRowSlot.body);
  RenderBox? get _trailing => childForSlot(AdaptiveRowSlot.trailing);

  /* Works out the layout with [layoutChild] (a real or a dry layout) and
     returns this box's size, plus where each child goes. */
  ({Size size, Offset leading, Offset body, Offset trailing}) _compute(
    BoxConstraints constraints,
    ChildLayouter layoutChild,
  ) {
    final maxW = constraints.maxWidth;
    final loose = BoxConstraints(maxWidth: maxW);
    Size sizeOf(RenderBox? child, BoxConstraints c) =>
        child == null ? Size.zero : layoutChild(child, c);

    final lead = sizeOf(_leading, loose);
    final trail = sizeOf(_trailing, loose);
    final leadPart = _leading == null ? 0.0 : lead.width + _gap;
    final trailPart = _trailing == null ? 0.0 : trail.width + _trailingGap;

    if (!maxW.isFinite) {
      // Nothing to squeeze against: a plain row at natural sizes.
      final body = sizeOf(_body, const BoxConstraints());
      final h = [lead.height, body.height, trail.height].reduce(math.max);
      return (
        size: constraints.constrain(
          Size(leadPart + body.width + trailPart, h),
        ),
        leading: Offset(0, (h - lead.height) / 2),
        body: Offset(leadPart, (h - body.height) / 2),
        trailing: Offset(leadPart + body.width + _trailingGap, (h - trail.height) / 2),
      );
    }

    final sideBySide = maxW - leadPart - trailPart;
    final stacked = _trailing != null && sideBySide < _minBodyWidth;

    if (!stacked) {
      final bodyW = math.max(0.0, sideBySide);
      final body = sizeOf(_body, BoxConstraints.tightFor(width: bodyW));
      final h = [lead.height, body.height, trail.height].reduce(math.max);
      final size = constraints.constrain(Size(maxW, h));
      return (
        size: size,
        leading: Offset(0, (size.height - lead.height) / 2),
        body: Offset(leadPart, (size.height - body.height) / 2),
        trailing: Offset(maxW - trail.width, (size.height - trail.height) / 2),
      );
    }

    final bodyW = math.max(0.0, maxW - leadPart);
    final body = sizeOf(_body, BoxConstraints.tightFor(width: bodyW));
    final topH = math.max(lead.height, body.height);
    final size = constraints.constrain(Size(maxW, topH + _runGap + trail.height));
    return (
      size: size,
      leading: Offset(0, (topH - lead.height) / 2),
      body: Offset(leadPart, (topH - body.height) / 2),
      trailing: Offset(maxW - trail.width, topH + _runGap),
    );
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _compute(constraints, ChildLayoutHelper.dryLayoutChild).size;

  @override
  void performLayout() {
    final r = _compute(constraints, ChildLayoutHelper.layoutChild);
    size = r.size;
    void place(RenderBox? child, Offset at) {
      if (child != null) (child.parentData! as BoxParentData).offset = at;
    }

    place(_leading, r.leading);
    place(_body, r.body);
    place(_trailing, r.trailing);
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    final lead = _leading?.getMinIntrinsicWidth(height) ?? 0;
    final body = _body?.getMinIntrinsicWidth(height) ?? 0;
    final trail = _trailing?.getMinIntrinsicWidth(height) ?? 0;
    return math.max(lead + (_leading == null ? 0 : _gap) + body, trail);
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    final lead = _leading?.getMaxIntrinsicWidth(height) ?? 0;
    final body = _body?.getMaxIntrinsicWidth(height) ?? 0;
    final trail = _trailing?.getMaxIntrinsicWidth(height) ?? 0;
    return lead +
        (_leading == null ? 0 : _gap) +
        body +
        (_trailing == null ? 0 : _trailingGap + trail);
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _compute(BoxConstraints(maxWidth: width), ChildLayoutHelper.dryLayoutChild)
          .size
          .height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final body = _body;
    if (body == null) return null;
    final at = body.getDistanceToActualBaseline(baseline);
    return at == null ? null : at + (body.parentData! as BoxParentData).offset.dy;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in children) {
      context.paintChild(child, offset + (child.parentData! as BoxParentData).offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in children.toList().reversed) {
      final hit = result.addWithPaintOffset(
        offset: (child.parentData! as BoxParentData).offset,
        position: position,
        hitTest: (result, transformed) => child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }
}
