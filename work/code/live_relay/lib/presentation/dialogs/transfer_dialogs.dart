
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../application/transfer/transfer_models.dart';
import '../../application/vault_merge_service.dart';
import '../../core/domain/entities.dart';
import '../../core/ports/transfer_medium.dart';
import '../../core/transfer/webdav_connection.dart';
import '../../infrastructure/transfer/directory_transfer_medium.dart';
import '../../infrastructure/transfer/file_set_transfer_medium.dart';
import '../../infrastructure/transfer/webdav_transfer_medium.dart';
import 'backup_dialogs.dart';
import 'local_file_dialogs.dart';

/// Opens a medium for the transfer flows. With a cloud connection configured
/// the caller first picks between the cloud drive and a local directory; the
/// local path is a directory when it is writable through dart:io, otherwise a
/// user-picked file set. Android SAF tree paths usually come back as strings
/// dart:io cannot write, which is exactly the case the fallback covers.
Future<TransferMedium?> openTransferMedium(
  BuildContext context,
  AppController controller, {
  required String title,
  required bool forExport,
}) async {
  final connection = await controller.webDavConnection();
  if (!context.mounted) return null;
  if (connection != null) {
    final useCloud = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('选择介质'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('云端 · ${connection.describe}'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('本地目录（U 盘 / 局域网盘 / 挂载目录）'),
          ),
        ],
      ),
    );
    if (useCloud == null || !context.mounted) return null;
    if (useCloud) {
      return WebDavTransferMedium(
        baseUrl: connection.baseUrl,
        username: connection.username,
        password: connection.password,
      );
    }
  }
  final directory = await pickLocalDirectory(title: title);
  if (directory == null) return null;
  if (await DirectoryTransferMedium.probeWritable(directory)) {
    return DirectoryTransferMedium(directory);
  }
  if (!context.mounted) return null;
  final useFiles = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('这个目录没法直接读写'),
      content: const Text('此设备不能把所选目录当 U 盘用（常见于手机上的安全目录）。改用逐个选择文件的方式继续吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('改用文件方式'),
        ),
      ],
    ),
  );
  if (useFiles != true || !context.mounted) return null;
  final files = await FilePicker.pickFiles(
    dialogTitle: forExport
        ? '选择介质上已有的备份包（可全不选，新包将逐个保存）'
        : '选择介质上的备份包（数据库包与原件卷）',
  );
  if (!context.mounted) return null;
  return FileSetTransferMedium([
    for (final file in files)
      MediumSourceFile(
        name: file.name,
        length: file.lengthSync(),
        readBytes: file.readAsBytes,
      ),
  ]);
}

/// Configures or clears the device-local cloud drive connection. The
/// entered values can be checked against the server before saving.
Future<void> showWebDavConnectionDialog(
  BuildContext context,
  AppController controller,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final existing = await controller.webDavConnection();
  if (!context.mounted) return;
  final result = await showDialog<_ConnectionEdit>(
    context: context,
    builder: (_) => _WebDavConnectionDialog(existing: existing),
  );
  if (result == null || !context.mounted) return;
  try {
    if (result.clear) {
      await controller.clearWebDavConnection();
      if (messenger.mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('云端连接已清除')));
      }
      return;
    }
    final connection = WebDavConnection.parse(
      url: result.url,
      username: result.username,
      password: result.password,
    );
    if (connection == null) return;
    await controller.saveWebDavConnection(connection);
    if (messenger.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('云端连接已保存：${connection.describe}')),
      );
    }
  } on Object {
    if (messenger.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(controller.lastError ?? '云端连接保存失败')),
      );
    }
  }
}

class _ConnectionEdit {
  const _ConnectionEdit({
    required this.url,
    required this.username,
    required this.password,
  }) : clear = false;

  const _ConnectionEdit.clear()
    : url = '',
      username = '',
      password = '',
      clear = true;

  final String url;
  final String username;
  final String password;
  final bool clear;
}

class _WebDavConnectionDialog extends StatefulWidget {
  const _WebDavConnectionDialog({this.existing});

  final WebDavConnection? existing;

  @override
  State<_WebDavConnectionDialog> createState() =>
      _WebDavConnectionDialogState();
}

class _WebDavConnectionDialogState extends State<_WebDavConnectionDialog> {
  late final TextEditingController url = TextEditingController(
    text: widget.existing?.baseUrl.toString() ?? '',
  );
  late final TextEditingController username = TextEditingController(
    text: widget.existing?.username ?? '',
  );
  late final TextEditingController password = TextEditingController(
    text: widget.existing?.password ?? '',
  );
  String? error;
  String? checkMessage;
  var checking = false;

  @override
  void dispose() {
    url.dispose();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> check() async {
    final validation = WebDavConnection.validationError(
      url: url.text,
      username: username.text,
      password: password.text,
    );
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    final connection = WebDavConnection.parse(
      url: url.text,
      username: username.text,
      password: password.text,
    )!;
    setState(() {
      checking = true;
      error = null;
      checkMessage = null;
    });
    final medium = WebDavTransferMedium(
      baseUrl: connection.baseUrl,
      username: connection.username,
      password: connection.password,
      timeout: const Duration(seconds: 15),
    );
    try {
      final entries = await medium.list();
      if (mounted) {
        setState(
          () => checkMessage = '连接成功：云端目录里现有 ${entries.length} 个文件',
        );
      }
    } on Object catch (failure) {
      if (mounted) setState(() => checkMessage = '$failure');
    } finally {
      medium.close();
      if (mounted) setState(() => checking = false);
    }
  }

  void save() {
    final validation = WebDavConnection.validationError(
      url: url.text,
      username: username.text,
      password: password.text,
    );
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    Navigator.pop(
      context,
      _ConnectionEdit(
        url: url.text,
        username: username.text,
        password: password.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('云端连接（WebDAV）'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('填服务商或自建服务给你的网址、账号和密码。密码只保存在这台设备上，不进入加密库、不随整库搬运。'),
            const SizedBox(height: 12),
            TextField(
              controller: url,
              autofocus: true,
              enabled: !checking,
              decoration: const InputDecoration(
                labelText: '网址（含路径，如 https://drive.example.com/alice/）',
              ),
            ),
            TextField(
              controller: username,
              enabled: !checking,
              decoration: const InputDecoration(labelText: '账号'),
            ),
            TextField(
              controller: password,
              obscureText: true,
              enabled: !checking,
              onSubmitted: (_) => save(),
              decoration: const InputDecoration(labelText: '密码'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (checkMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(checkMessage!),
              ),
            if (checking) const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            onPressed: checking
                ? null
                : () => Navigator.pop(context, const _ConnectionEdit.clear()),
            child: const Text('清除'),
          ),
        TextButton(
          onPressed: checking ? null : check,
          child: const Text('测试连接'),
        ),
        TextButton(
          onPressed: checking ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: checking ? null : save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// Exports the whole vault to a chosen medium directory: the database package
/// is rewritten, originals ride in append-only volumes.
Future<void> exportToMediumFlow(
  BuildContext context,
  AppController controller,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final medium = await openTransferMedium(
      context,
      controller,
      title: '选择介质目录（U 盘 / 局域网盘 / WebDAV 挂载目录）',
      forExport: true,
    );
    if (medium == null || !context.mounted) return;
    final credential = await showDialog<String>(
      context: context,
      builder: (_) => const PasswordPromptDialog(
        title: '验证备份：密码或独立恢复凭证',
        actionLabel: '导出到介质',
      ),
    );
    if (credential == null || !context.mounted) return;
    final outcome = await controller.exportToMedium(medium, credential);
    if (!context.mounted) return;
    await _showInfo(
      context,
      title: '已导出到介质',
      lines: [
        '数据库包：${outcome.databaseName}（每趟覆盖更新）',
        '本轮新写原件卷：${outcome.writtenVolumes.length} 个',
        '介质上已有原件卷被复用，跳过原件：${outcome.skippedBlobs} 个',
        if (!outcome.indexPersisted)
          '注意：本机导出索引未能保存；下次导出可能重写同样的卷。',
        ...outcome.warnings,
        '介质：${medium.label}',
      ],
    );
  } on Object {
    if (messenger.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(controller.lastError ?? '导出到介质失败')),
      );
    }
  } finally {
    try {
      await FilePicker.clearTemporaryFiles();
    } on Object {
      /* retry on next start */
    }
  }
}

/// Imports a whole vault from the medium: pick the directory, confirm the
/// replacement (optionally exporting the current vault first), then let the
/// service restore the database package and consume the paired volumes.
Future<void> importFromMediumFlow(
  BuildContext context,
  AppController controller,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final medium = await openTransferMedium(
      context,
      controller,
      title: '选择介质目录（U 盘 / 局域网盘 / WebDAV 挂载目录）',
      forExport: false,
    );
    if (medium == null || !context.mounted) return;
    final scan = await controller.scanTransferMedium(medium);
    if (!context.mounted) return;
    final database = await _chooseDatabase(context, scan);
    if (database == null || !context.mounted) return;
    final credential = await showDialog<String>(
      context: context,
      builder: (_) => const PasswordPromptDialog(
        title: '输入介质中资料库的密码或独立恢复凭证',
        actionLabel: '核对介质内容',
      ),
    );
    if (credential == null || !context.mounted) return;
    final preview = await controller.inspectTransferMedium(
      medium,
      database.name,
      credential,
    );
    if (!context.mounted) return;

    final missing = await controller.missingOriginalCount();
    if (!context.mounted) return;
    final volumes = scan.volumesMatching(database.snapshotId);
    final replacing = controller.header != null;
    // B 模式触发（口径）：介质包的 vaultId 与本机一致且已解锁时可合并导入；
    // 异血统包禁用合并并提示用替换导入。
    final myVaultId = await controller.archiveVaultId();
    if (!context.mounted) return;
    final sameVault =
        database.vaultId != null && database.vaultId == myVaultId;
    final canMerge = replacing && controller.isUnlocked && sameVault;
    final foreignVault = replacing &&
        controller.isUnlocked &&
        database.vaultId != null &&
        myVaultId != null &&
        !sameVault;
    final decision = await showDialog<
      ({bool confirmed, bool preExport, bool merge})
    >(
      context: context,
      builder: (_) => _ImportConfirmDialog(
        preview: preview,
        database: database,
        volumeCount: volumes.length,
        replacing: replacing,
        canPreExport: controller.isUnlocked && missing == 0,
        preExportReason: !controller.isUnlocked
            ? '当前资料库未解锁，无法先导出'
            : missing > 0
            ? '当前还有 $missing 个原件未补齐，请先补齐再导出'
            : null,
        canMerge: canMerge,
        foreignVault: foreignVault,
      ),
    );
    if (decision == null || !decision.confirmed || !context.mounted) return;

    if (decision.merge) {
      final report = await controller.mergeFromMedium(
        medium,
        databaseName: database.name,
        credential: credential,
      );
      if (!context.mounted) return;
      await _showMergeReport(context, report);
      return;
    }

    String? preExportCredential;
    if (decision.preExport) {
      preExportCredential = await showDialog<String>(
        context: context,
        builder: (_) => const PasswordPromptDialog(
          title: '输入当前资料库的密码或独立恢复凭证',
          actionLabel: '先导出当前库',
        ),
      );
      if (preExportCredential == null || !context.mounted) return;
    }

    final report = await controller.importFromMedium(
      medium,
      databaseName: database.name,
      credential: credential,
      preExportCredential: preExportCredential,
    );
    if (!context.mounted) return;
    await _showTransferReport(context, report);
  } on Object {
    if (messenger.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(controller.lastError ?? '从介质导入失败')),
      );
    }
  } finally {
    try {
      await FilePicker.clearTemporaryFiles();
    } on Object {
      /* retry on next start */
    }
  }
}

/// Completes owed originals from the medium after a required security reset
/// (or after a partial import).
Future<void> topUpOriginalsFromMediumFlow(
  BuildContext context,
  AppController controller,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final medium = await openTransferMedium(
      context,
      controller,
      title: '选择介质目录（U 盘 / 局域网盘 / WebDAV 挂载目录）',
      forExport: false,
    );
    if (medium == null || !context.mounted) return;
    final report = await controller.importPendingVolumes(medium);
    if (!context.mounted) return;
    await _showTransferReport(context, report);
  } on Object {
    if (messenger.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(controller.lastError ?? '从介质补齐原件失败')),
      );
    }
  } finally {
    try {
      await FilePicker.clearTemporaryFiles();
    } on Object {
      /* retry on next start */
    }
  }
}

Future<MediumPackage?> _chooseDatabase(
  BuildContext context,
  TransferMediumScan scan,
) async {
  final recognized = scan.databases;
  if (recognized.isEmpty) {
    await _showInfo(
      context,
      title: '介质上没有找到数据库包',
      lines: [
        if (scan.unmatched.isNotEmpty)
          '目录里这些文件无法识别：${scan.unmatched.map((p) => p.name).join('、')}',
        ...scan.warnings,
        '请确认选择的是导出时所在的目录。',
      ],
    );
    return null;
  }
  if (recognized.length == 1) return recognized.single;
  return showDialog<MediumPackage>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('介质上有多个数据库包，选择要导入的一个'),
      children: [
        for (final database in recognized)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, database),
            child: Text(_describePackage(database)),
          ),
      ],
    ),
  );
}

String _describePackage(MediumPackage package) {
  final created = package.createdAt?.toLocal();
  final stamp = created == null
      ? '时间未记录'
      : '${created.year}-${created.month.toString().padLeft(2, '0')}-'
            '${created.day.toString().padLeft(2, '0')} '
            '${created.hour.toString().padLeft(2, '0')}:'
            '${created.minute.toString().padLeft(2, '0')}';
  return '${package.name}（$stamp）';
}

class _ImportConfirmDialog extends StatefulWidget {
  const _ImportConfirmDialog({
    required this.preview,
    required this.database,
    required this.volumeCount,
    required this.replacing,
    required this.canPreExport,
    this.preExportReason,
    this.canMerge = false,
    this.foreignVault = false,
  });

  final BackupPreview preview;
  final MediumPackage database;
  final int volumeCount;
  final bool replacing;
  final bool canPreExport;
  final String? preExportReason;

  /// 包与本机同血统且已解锁：可选合并导入。
  final bool canMerge;

  /// 包来自另一套资料库：只能替换，界面明说原因。
  final bool foreignVault;

  @override
  State<_ImportConfirmDialog> createState() => _ImportConfirmDialogState();
}

class _ImportConfirmDialogState extends State<_ImportConfirmDialog> {
  var preExport = false;
  late var merge = widget.canMerge;

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final created = preview.createdAt?.toLocal();
    return AlertDialog(
      title: Text(
        merge
            ? '核对介质内容并合并导入'
            : widget.replacing
            ? '核对介质内容并替换当前资料库'
            : '核对介质内容并导入资料库',
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('口令、完整性和数据库已验证。'),
            Text('介质包：${widget.database.name}'),
            if (created != null)
              Text(
                '导出时间：${created.year}-${created.month.toString().padLeft(2, '0')}-'
                '${created.day.toString().padLeft(2, '0')} '
                '${created.hour.toString().padLeft(2, '0')}:'
                '${created.minute.toString().padLeft(2, '0')}',
              ),
            Text(
              '${preview.cards} 张卡片 · ${preview.credentials} 条密码 · ${preview.originals} 个原件',
            ),
            const SizedBox(height: 12),
            if (widget.canMerge) ...[
              const Text('导入方式'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('合并导入'),
                    selected: merge,
                    onSelected: (_) => setState(() => merge = true),
                  ),
                  ChoiceChip(
                    label: const Text('替换导入'),
                    selected: !merge,
                    onSelected: (_) => setState(() => merge = false),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                merge
                    ? '保留本机内容；另一台设备新增和修改的卡片合并进来。两台设备改过同一张卡时先保留本机版，并在卡片上标记，稍后可以切换。'
                    : '导入成功后当前资料库全部由介质内容替换，不会合并。',
              ),
            ] else if (widget.foreignVault)
              const Text('这个包来自另一套资料库，无法合并，只能替换导入。')
            else
              Text(
                widget.replacing
                    ? '导入成功后当前资料库全部由介质内容替换，不会合并。'
                    : '导入后即为完整资料库。',
              ),
            if (widget.volumeCount > 0)
              Text(
                '介质上有 ${widget.volumeCount} 个与本包配对的原件卷，导入数据库后自动补齐；'
                '本机已有的原件会就地复用。',
              )
            else if (preview.missingOriginals > 0)
              Text(
                '介质上没有配对的原件卷：导入后将缺 ${preview.missingOriginals} 个原件，需要另行补齐。',
              ),
            if (merge)
              const Text('合并后用本机现在的密码解锁；另一台设备的凭证不进入本机。')
            else
              Text(
                preview.requiresReset
                    ? '该库的解锁方式在这台设备上用不了：导入后先在本机完成安全重设，再用"从介质补齐原件"完成原件卷。'
                    : '导入成功后可直接进入资料库；解锁凭证保持该库自带的密码。',
              ),
            if (!merge) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: preExport,
                onChanged: widget.canPreExport
                    ? (value) => setState(() => preExport = value ?? false)
                    : null,
                title: const Text('先把当前库导出到介质再替换'),
                subtitle: Text(
                  widget.canPreExport
                      ? '多验证一次当前库的凭证；替换后仍可从介质找回。'
                      : widget.preExportReason ?? '',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            (confirmed: false, preExport: false, merge: false),
          ),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            (confirmed: true, preExport: merge ? false : preExport, merge: merge),
          ),
          child: Text(
            merge
                ? '确认合并导入'
                : widget.replacing
                ? '确认替换并导入'
                : '确认导入',
          ),
        ),
      ],
    );
  }
}

Future<void> _showTransferReport(
  BuildContext context,
  TransferImportReport report,
) async {
  final lines = <String>[
    if (report.databaseName != null) '数据库包：${report.databaseName}',
    if (report.preExport != null) '替换前已把原资料库导出到介质。',
    '从本机旧库就地复用原件：${report.harvestedOriginals} 个',
    '核验消费的原件卷：${report.volumesConsumed} 个',
    if (report.requiresReset)
      '该库的解锁方式在这台设备上用不了：请先完成本机安全重设；'
          '重设后在「设备间搬运」页用"从介质补齐原件"完成剩下的 ${report.pendingVolumes.length} 个原件卷。'
    else if (report.remainingMissingOriginals > 0)
      '还缺 ${report.remainingMissingOriginals} 个原件；介质上可能缺少对应卷，或缺卷文件没有拷全。'
    else
      '原件已补齐。',
    ...report.volumeErrors,
  ];
  await _showInfo(context, title: '导入结果', lines: lines);
}

Future<void> _showMergeReport(
  BuildContext context,
  MergeImportReport report,
) async {
  final lines = <String>[
    '数据库包：${report.databaseName}',
    '另一台设备带来的卡片：新增 ${report.importedCards} · 单边跟进 ${report.fastForwardedCards} · 两边都改过 ${report.forkedCards}',
    if (report.adoptedDeletions > 0)
      '采用另一台设备的删除：${report.adoptedDeletions} 条',
    if (report.keptLocalDeletionConflicts > 0)
      '另一台设备删过、本机改过的卡片：${report.keptLocalDeletionConflicts} 条（保留本机版，已标记）',
    if (report.localDeletionConflicts > 0)
      '本机删过、另一台设备改过的卡片：${report.localDeletionConflicts} 条（保持删除，可恢复后采用对方版本）',
    if (report.referenceChanges.isNotEmpty)
      '卡片引用更新：${report.referenceChanges.length} 张',
    '原件：本机无的新增 ${report.importedBlobs}（同钥直拷 ${report.copiedBlobs} · 重新加密 ${report.reencryptedBlobs} · 复用本机 ${report.reusedLocalBlobs}）',
    '核验消费的原件卷：${report.volumesConsumed} 个',
    if (report.owedBlobs > 0)
      '包内没带的原件：${report.owedBlobs} 个，已记入待补齐',
    if (report.remainingMissingOriginals > 0)
      '还缺 ${report.remainingMissingOriginals} 个原件；可在「设备间搬运」用"从介质补齐原件"完成。'
    else
      '原件已补齐。',
    ...report.volumeErrors,
    ...report.warnings,
    if (report.conflicts.isNotEmpty) ...[
      '需要选择保留哪个版本的卡片 ${report.conflicts.length} 张：',
      for (final conflict in report.conflicts.take(8)) '· ${conflict.title}',
      if (report.conflicts.length > 8)
        '· 等 ${report.conflicts.length} 张（在列表里有标记）',
    ],
    '未合并（保留本机）：${report.unmergedCategories.join('、')}。',
  ];
  await _showInfo(context, title: '合并导入结果', lines: lines);
}

Future<void> _showInfo(
  BuildContext context, {
  required String title,
  required List<String> lines,
}) => showDialog<void>(
  context: context,
  builder: (c) => AlertDialog(
    title: Text(title),
    content: SingleChildScrollView(child: Text(lines.join('\n'))),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(c),
        child: const Text('好'),
      ),
    ],
  ),
);
