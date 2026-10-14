/// Device-local cloud drive connection: the URL, account and password of the
/// user's WebDAV medium. Kept with the other device preferences (outside the
/// encrypted vault), so it never travels inside a vault package.
class WebDavConnection {
  const WebDavConnection({
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  final Uri baseUrl;
  final String username;
  final String password;

  String get describe {
    final path = baseUrl.path == '/' ? '' : baseUrl.path;
    return '${baseUrl.host}$path · $username';
  }

  static String? validationError({
    required String url,
    required String username,
    required String password,
  }) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return '网址需要是完整的 http:// 或 https:// 地址';
    }
    if (username.trim().isEmpty) return '账号不能为空';
    if (password.isEmpty) return '密码不能为空';
    return null;
  }

  static WebDavConnection? parse({
    required String url,
    required String username,
    required String password,
  }) {
    if (validationError(url: url, username: username, password: password) !=
        null) {
      return null;
    }
    return WebDavConnection(
      baseUrl: Uri.parse(url.trim()),
      username: username.trim(),
      password: password,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'url': baseUrl.toString(),
    'username': username,
    'password': password,
  };

  /// Null when the record is unreadable or invalid; callers treat that as
  /// "not configured" rather than guessing.
  static WebDavConnection? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final url = raw['url'], username = raw['username'], password = raw['password'];
    if (url is! String || username is! String || password is! String) {
      return null;
    }
    return parse(url: url, username: username, password: password);
  }
}
