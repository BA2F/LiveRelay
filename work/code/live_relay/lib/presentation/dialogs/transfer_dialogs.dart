
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../application/transfer/transfer_models.dart';
import '../../core/domain/entities.dart';
import '../../core/ports/transfer_medium.dart';
import '../../infrastructure/transfer/directory_transfer_medium.dart';
import '../../infrastructure/transfer/file_set_transfer_medium.dart';
import 'backup_dialogs.dart';
import 'local_file_dialogs.dart';

/// Opens a medium for the transfer flows: a directory when it is writable
/// through dart:io, otherwise a user-picked file set. Android SAF tree paths
/// usually come back as strings dart:io cannot write, which is exactly the
/// case the fallback covers.
Future<TransferMedium?> openTransferMedium(
  BuildContext context, {
  required String title,
  required bool forExport,
}) async {
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
    final decision = await showDialog<({bool confirmed, bool preExport})>(
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
      ),
    );
    if (decision == null || !decision.confirmed || !context.mounted) return;

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
  });

  final BackupPreview preview;
  final MediumPackage database;
  final int volumeCount;
  final bool replacing;
  final bool canPreExport;
  final String? preExportReason;

  @override
  State<_ImportConfirmDialog> createState() => _ImportConfirmDialogState();
}

class _ImportConfirmDialogState extends State<_ImportConfirmDialog> {
  var preExport = false;

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final created = preview.createdAt?.toLocal();
    return AlertDialog(
      title: Text(widget.replacing ? '核对介质内容并替换当前资料库' : '核对介质内容并导入资料库'),
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
            Text(
              preview.requiresReset
                  ? '该库的解锁方式在这台设备上用不了：导入后先在本机完成安全重设，再用"从介质补齐原件"完成原件卷。'
                  : '导入成功后可直接进入资料库；解锁凭证保持该库自带的密码。',
            ),
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
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, (confirmed: false, preExport: false)),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (confirmed: true, preExport: preExport)),
          child: Text(widget.replacing ? '确认替换并导入' : '确认导入'),
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
