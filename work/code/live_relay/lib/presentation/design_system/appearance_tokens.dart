import 'dart:ui';

import 'package:flutter/material.dart';

class AppearanceTokens extends ThemeExtension<AppearanceTokens> {
  const AppearanceTokens({
    this.cardRadius = 20,
    this.fieldRadius = 16,
    this.pageInset = 16,
  });
  final double cardRadius;
  final double fieldRadius;
  final double pageInset;
  static AppearanceTokens of(BuildContext context) =>
      Theme.of(context).extension<AppearanceTokens>() ??
      const AppearanceTokens();
  @override
  AppearanceTokens copyWith({
    double? cardRadius,
    double? fieldRadius,
    double? pageInset,
  }) => AppearanceTokens(
    cardRadius: cardRadius ?? this.cardRadius,
    fieldRadius: fieldRadius ?? this.fieldRadius,
    pageInset: pageInset ?? this.pageInset,
  );
  @override
  AppearanceTokens lerp(covariant AppearanceTokens? other, double t) =>
      other == null
      ? this
      : AppearanceTokens(
          cardRadius: lerpDouble(cardRadius, other.cardRadius, t)!,
          fieldRadius: lerpDouble(fieldRadius, other.fieldRadius, t)!,
          pageInset: lerpDouble(pageInset, other.pageInset, t)!,
        );
}
