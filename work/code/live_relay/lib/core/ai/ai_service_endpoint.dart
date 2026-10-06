import '../ports/ai_provider.dart';

/// Accept conventional base URLs as well as complete, custom service routes.
/// This only changes the path on the explicitly selected host; never retries
/// another host/protocol or follows a redirect with supplied credentials/data.
Uri resolveAiEndpoint(Uri endpoint, AiProtocol protocol) {
  final path = endpoint.path.replaceFirst(RegExp(r'/+$'), '');
  final route = protocol == AiProtocol.responses
      ? '/responses'
      : '/chat/completions';
  final String prefix;
  if (path.endsWith('/chat/completions')) {
    prefix = path.substring(0, path.length - '/chat/completions'.length);
  } else if (path.endsWith('/responses')) {
    prefix = path.substring(0, path.length - '/responses'.length);
  } else if (path.isEmpty || path == '/v1') {
    prefix = path;
  } else {
    return endpoint; // A custom full route is intentional, not a guessed base.
  }
  return endpoint.replace(path: '$prefix$route');
}

String aiHttpFailure(String operation, int status) => status == 404
    ? '$operation失败（HTTP 404）；请核对实际请求地址、所选协议和模型名。'
    : '$operation失败（HTTP $status）';
