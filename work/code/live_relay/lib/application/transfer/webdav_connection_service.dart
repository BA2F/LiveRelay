import '../../core/ports/webdav_connection_repository.dart';
import '../../core/transfer/webdav_connection.dart';

/// Caches the device-local cloud connection so pages and dialogs can read it
/// synchronously after the first load; writes go through to storage first.
class WebDavConnectionService {
  WebDavConnectionService(this._repository);

  final WebDavConnectionRepository _repository;
  WebDavConnection? _cached;
  var _loaded = false;

  Future<WebDavConnection?> current() async {
    if (!_loaded) {
      _cached = await _repository.read();
      _loaded = true;
    }
    return _cached;
  }

  Future<void> save(WebDavConnection connection) async {
    await _repository.write(connection);
    _cached = connection;
    _loaded = true;
  }

  Future<void> clear() async {
    await _repository.clear();
    _cached = null;
    _loaded = true;
  }
}
