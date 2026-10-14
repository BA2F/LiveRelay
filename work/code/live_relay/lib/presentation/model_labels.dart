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
    CardStatus.draft => '待整理',
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
    LifeState.deceased => Icons.flag_outlined,
  };
}

extension VisibilityPresentation on VisibilityLevel {
  String get label => switch (this) {
    VisibilityLevel.hidden => '保持私密',
    VisibilityLevel.existence => '只知道有这条信息',
    VisibilityLevel.summary => '基本信息',
    VisibilityLevel.full => '完整内容',
    VisibilityLevel.secret => '含密码 / 密钥',
    VisibilityLevel.original => '含原始资料',
  };
}

extension SourceKindPresentation on SourceKind {
  String get label => switch (this) {
    SourceKind.ownerInput => '本人输入',
    SourceKind.imported => '导入',
    SourceKind.ocrDerived => '识别文字',
    SourceKind.aiGenerated => '模型生成',
    SourceKind.photo => '照片',
    SourceKind.audio => '录音',
    SourceKind.video => '视频',
  };
}

extension BlobMediaKindPresentation on BlobMediaKind {
  String get label => switch (this) {
    BlobMediaKind.image => '图片',
    BlobMediaKind.audio => '录音',
    BlobMediaKind.video => '视频',
    BlobMediaKind.document => '文档',
    BlobMediaKind.other => '文件',
  };
}
