class AgentCommandResult {
  const AgentCommandResult({
    required this.command,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
  final String command;
  final int exitCode;
  final String stdout;
  final String stderr;
  Map<String, Object?> toJson() => {
    'exit_code': exitCode,
    'stdout': stdout,
    'stderr': stderr,
  };
}

abstract interface class AgentCommandSession {
  List<AgentCommandResult> get history;
  Future<AgentCommandResult> run(String command);
  Future<void> close();
}

abstract interface class AgentCommandProvider {
  Future<bool> available();
  Future<AgentCommandSession> open(
    String redactedText, {
    Future<void>? whenCancelled,
  });
}
