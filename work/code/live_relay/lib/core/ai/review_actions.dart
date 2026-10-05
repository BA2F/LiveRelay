import '../domain/entities.dart';

/// Explicit owner choices for one reviewed card. Never populated by AI text.
class ReviewActions {
  const ReviewActions({
    this.bundleId,
    this.referenceIds = const [],
    this.incapacitated = VisibilityLevel.hidden,
    this.deceased = VisibilityLevel.hidden,
  });
  final String? bundleId;
  final List<String> referenceIds;
  final VisibilityLevel incapacitated, deceased;
  bool get hasChanges =>
      bundleId != null ||
      referenceIds.isNotEmpty ||
      incapacitated != VisibilityLevel.hidden ||
      deceased != VisibilityLevel.hidden;
  static const cardLevels = [
    VisibilityLevel.hidden,
    VisibilityLevel.existence,
    VisibilityLevel.summary,
    VisibilityLevel.full,
    VisibilityLevel.original,
  ];
  Map<String, Object?> toJson() => {
    'bundle': bundleId,
    'references': referenceIds,
    'incapacitated': incapacitated.name,
    'deceased': deceased.name,
  };
  factory ReviewActions.fromJson(Map raw) {
    final result = ReviewActions(
      bundleId: raw['bundle'] as String?,
      referenceIds: List<String>.from(raw['references'] as List),
      incapacitated: VisibilityLevel.values.byName(
        raw['incapacitated'] as String,
      ),
      deceased: VisibilityLevel.values.byName(raw['deceased'] as String),
    );
    result.validate();
    return result;
  }
  void validate() {
    if (referenceIds.length > 200 ||
        referenceIds.toSet().length != referenceIds.length ||
        referenceIds.any((id) => id.isEmpty || id.length > 64) ||
        (bundleId != null && (bundleId!.isEmpty || bundleId!.length > 64)) ||
        !cardLevels.contains(incapacitated) ||
        !cardLevels.contains(deceased)) {
      throw const FormatException('确认操作计划无效');
    }
  }
}
