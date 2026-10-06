import 'review_actions.dart';

/// IDs of cards explicitly attached to this turn, without further vault data.
class ReviewTarget {
  const ReviewTarget(this.id, {required this.bundle});
  final String id;
  final bool bundle;
  Map<String, Object?> toJson() => {'id': id, 'bundle': bundle};
}

/// Untrusted model proposal. It is never an executable owner choice by itself.
class ReviewActionProposal {
  const ReviewActionProposal(this.plan, {this.reason = ''});
  final ReviewActions plan;
  final String reason;

  static ReviewActionProposal parse(Map raw, List<ReviewTarget> targets) {
    final proposal = ReviewActionProposal.fromJson(raw);
    if (proposal.plan.referenceIds.any(
          (id) => !targets.any((t) => t.id == id),
        ) ||
        (proposal.plan.bundleId != null &&
            !targets.any((t) => t.id == proposal.plan.bundleId && t.bundle))) {
      throw const FormatException('模型操作草案引用了本轮未选择的目标');
    }
    return proposal;
  }

  factory ReviewActionProposal.fromJson(Map raw) {
    const allowed = {
      'bundle',
      'references',
      'incapacitated',
      'deceased',
      'reason',
    };
    if (raw.keys.toSet().difference(allowed).isNotEmpty ||
        (raw['reason'] != null && raw['reason'] is! String)) {
      throw const FormatException('模型操作草案字段无效');
    }
    try {
      final result = ReviewActionProposal(
        ReviewActions.fromJson(raw),
        reason: raw['reason'] as String? ?? '',
      );
      result.validate();
      return result;
    } on Object {
      throw const FormatException('模型操作草案结构无效');
    }
  }

  void validate() {
    plan.validate();
    if (reason.length > 1000) throw const FormatException('模型操作草案说明过长');
  }

  Map<String, Object?> toJson() => {...plan.toJson(), 'reason': reason};
}
