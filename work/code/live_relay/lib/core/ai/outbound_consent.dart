/// 跨端外发确认模型（2026-10-12 桌面重设计第 5 节）。
///
/// 确认粒度跟新增的风险走，不跟动作次数走：首次向某个服务发内容、首次发
/// 附件各拦一次；之后这类发送默认直接进行，不再每轮弹窗。授权按设备本地的
/// 服务配置记录，不进入加密库；服务地址变化视为新的服务，需要重新确认。
enum OutboundKind {
  /// 经本机脱敏（敏感行以占位符替换）后的文字内容。
  content('content'),

  /// 按原始内容发送的附件：图片、视频、音频、文档。
  attachment('attachment');

  const OutboundKind(this.wireName);
  final String wireName;

  static OutboundKind? fromWire(String value) {
    for (final kind in OutboundKind.values) {
      if (kind.wireName == value) return kind;
    }
    return null;
  }
}

/// 一次外发面对的服务目标。id 稳定标识服务，label 只用于界面文案。
class OutboundDestination {
  const OutboundDestination({required this.id, required this.label});
  final String id;
  final String label;

  static OutboundDestination ai({
    required String profileId,
    required String endpoint,
    required String name,
  }) => OutboundDestination(
    id: 'ai:$profileId@${Uri.tryParse(endpoint)?.host ?? endpoint}',
    label: '$name（${Uri.tryParse(endpoint)?.host ?? endpoint}）',
  );

  static OutboundDestination speech({
    required String endpoint,
    required String name,
  }) => OutboundDestination(
    id: 'speech@${Uri.tryParse(endpoint)?.host ?? endpoint}',
    label: '$name（${Uri.tryParse(endpoint)?.host ?? endpoint}）',
  );
}
