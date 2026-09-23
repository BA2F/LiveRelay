import 'package:flutter/material.dart';

import '../core/domain/entities.dart';

extension CardKindPresentation on CardKind {
  String get label => switch (this) {
    CardKind.note => '日常记录',
    CardKind.account => '账户',
    CardKind.asset => '资产',
    CardKind.debt => '负债',
    CardKind.location => '位置',
    CardKind.relationship => '人物关系',
    CardKind.document => '文档',
    CardKind.wish => '意愿',
    CardKind.familyOperation => '家庭运营',
    CardKind.bundle => '组合卡片',
  };

  IconData get icon => switch (this) {
    CardKind.note => Icons.notes_rounded,
    CardKind.account => Icons.account_circle_outlined,
    CardKind.asset => Icons.savings_outlined,
    CardKind.debt => Icons.receipt_long_outlined,
    CardKind.location => Icons.location_on_outlined,
    CardKind.relationship => Icons.people_outline,
    CardKind.document => Icons.description_outlined,
    CardKind.wish => Icons.favorite_outline,
    CardKind.familyOperation => Icons.home_work_outlined,
    CardKind.bundle => Icons.dashboard_customize_outlined,
  };
}

extension CardStatusPresentation on CardStatus {
  String get label => switch (this) {
    CardStatus.draft => '待确认',
    CardStatus.confirmed => '已确认',
    CardStatus.split => '已拆分',
    CardStatus.archived => '已归档',
  };
}

extension LifeStatePresentation on LifeState {
  String get label => switch (this) {
    LifeState.active => '健康 / 正常',
    LifeState.incapacitated => '临时失能',
    LifeState.deceased => '身故',
  };

  IconData get icon => switch (this) {
    LifeState.active => Icons.favorite_outline,
    LifeState.incapacitated => Icons.health_and_safety_outlined,
    LifeState.deceased => Icons.local_fire_department_outlined,
  };
}

extension VisibilityPresentation on VisibilityLevel {
  String get label => switch (this) {
    VisibilityLevel.hidden => '不释放',
    VisibilityLevel.existence => '仅存在性',
    VisibilityLevel.summary => '基本信息',
    VisibilityLevel.full => '完整内容',
    VisibilityLevel.secret => '含 Secret',
    VisibilityLevel.original => '含原始资料',
  };
}
