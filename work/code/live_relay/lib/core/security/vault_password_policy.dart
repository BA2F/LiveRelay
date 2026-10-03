class VaultPasswordPolicy {
  const VaultPasswordPolicy._();

  static const minimumLength = 8;

  static String? creationError(String password) {
    if (password.isEmpty) return '请输入主密码';
    if (password.length < minimumLength) {
      return '主密码至少需要 $minimumLength 个字符';
    }
    return null;
  }
}
