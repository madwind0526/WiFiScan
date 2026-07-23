import 'package:flutter/widgets.dart';

/// Reference width the layout was designed at. At or above this the UI renders
/// at full size; narrower screens shrink proportionally.
const double kLayoutReferenceWidth = 430;

/// How far below full size a phone may shrink. Below this the UI would get
/// hard to read, so text and controls stop shrinking and start wrapping.
const double kMinLayoutScale = 0.85;

/// Scale factor for paddings, icon sizes and text on a screen [width] wide.
///
/// A 360dp phone lands at [kMinLayoutScale], a large phone sits just under 1,
/// and tablets or desktop windows render at full size. Sizes and fonts shrink
/// together so a block that fits on desktop still fits on a phone.
double layoutScaleForWidth(double width) =>
    (width / kLayoutReferenceWidth).clamp(kMinLayoutScale, 1.0);

/// Scale factor for the screen [context] is rendered on.
double layoutScale(BuildContext context) =>
    layoutScaleForWidth(MediaQuery.sizeOf(context).width);

/// Applies [layoutScale] to the ambient text scaler, keeping the user's own
/// accessibility setting proportional: a 1.5x system scale stays 1.5x relative
/// to the phone-sized base rather than being thrown away.
MediaQueryData scaleTextFor(MediaQueryData media) {
  final systemFactor = media.textScaler.scale(14) / 14;
  final scale = layoutScaleForWidth(media.size.width);
  return media.copyWith(
    textScaler: TextScaler.linear(systemFactor * scale),
  );
}
