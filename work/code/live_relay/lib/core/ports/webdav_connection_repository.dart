import '../transfer/webdav_connection.dart';

abstract interface class WebDavConnectionRepository {
  /// Null when nothing is configured. Unreadable records raise instead of
  /// being treated as absent, so the user notices instead of silently
  /// re-entering credentials over a corrupt record.
  Future<WebDavConnection?> read();
  Future<void> write(WebDavConnection connection);
  Future<void> clear();
}
