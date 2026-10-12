import '../ai/outbound_consent.dart';

/// 设备本地的外发授权记录。授权跟随本机服务配置，不进入加密库，
/// 也不随整库搬运到其他设备。实现拥有具体存储，调用方不选插件。
abstract interface class OutboundConsentRepository {
  Future<Map<String, Set<OutboundKind>>> read();
  Future<void> write(Map<String, Set<OutboundKind>> grants);
}
