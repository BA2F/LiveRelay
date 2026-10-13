import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/transfer/transfer_models.dart';
import '../../infrastructure/transfer/directory_transfer_medium.dart';
import '../controllers/app_controller.dart';
import '../dialogs/local_file_dialogs.dart';
import '../dialogs/transfer_dialogs.dart';

/// C-mode device transfer（「整库搬运」）: export the whole vault to a
/// directory that acts as the medium, import it back on the other device.
class DeviceTransferPage extends StatefulWidget {
  const DeviceTransferPage({super.key});

  @override
  State<DeviceTransferPage> createState() => _DeviceTransferPageState();
}

class _DeviceTransferPageState extends State<DeviceTransferPage> {
  Directory? mediumDirectory;
  TransferMediumScan? scan;
  String? message;
  int missing = 0;

  @override
  void initState() {
    super.initState();
    refreshMissing();
  }

  Future<void> refreshMissing() async {
    final count = await context.read<AppController>().missingOriginalCount();
    if (mounted) setState(() => missing = count);
  }

  Future<void> chooseMedium() async {
    final controller = context.read<AppController>();
    try {
      final directory = await pickLocalDirectory(
        title: '选择介质目录（U 盘 / 局域网盘 / WebDAV 挂载目录）',
      );
      if (directory == null || !mounted) return;
      final result = await controller.scanTransferMedium(
        DirectoryTransferMedium(directory),
      );
      if (!mounted) return;
      setState(() {
        mediumDirectory = directory;
        scan = result;
        message = null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => message = '$error');
    }
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() => message = null);
    try {
      await action();
      await refreshMissing();
    } on Object catch (error) {
      if (mounted) setState(() => message = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final unlocked = controller.isUnlocked;
    final scan = this.scan;
    final database = scan?.databases.isEmpty ?? true
        ? null
        : scan!.databases.first;
    return Scaffold(
      appBar: AppBar(title: const Text('设备间搬运')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                '把整库搬到另一台设备：导出到一个介质目录（U 盘、数据线、局域网盘、WebDAV 挂载目录都当同一个目录用），'
                '在另一台设备上从同一个目录导入。导入就是整库替换，不做合并；'
                '原件按卷只增不改，第二次往来只搬新增的部分。',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: controller.isBusy || !unlocked
                    ? null
                    : () => run(() => exportToMediumFlow(context, controller)),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('导出到介质目录'),
              ),
              if (!unlocked) const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('导出需要先解锁资料库。'),
              ),
              OutlinedButton.icon(
                onPressed: controller.isBusy
                    ? null
                    : () =>
                          run(() => importFromMediumFlow(context, controller)),
                icon: const Icon(Icons.download_outlined),
                label: const Text('从介质导入（整库替换）'),
              ),
              OutlinedButton.icon(
                onPressed: controller.isBusy || !unlocked || missing == 0
                    ? null
                    : () => run(
                        () => topUpOriginalsFromMediumFlow(context, controller),
                      ),
                icon: const Icon(Icons.attach_file),
                label: Text(
                  missing == 0 ? '从介质补齐原件（当前无欠件）' : '从介质补齐原件（还缺 $missing 个）',
                ),
              ),
              const Divider(height: 32),
              Row(
                children: [
                  const Expanded(child: Text('介质内容')),
                  OutlinedButton(
                    onPressed: controller.isBusy ? null : chooseMedium,
                    child: const Text('选择介质目录'),
                  ),
                ],
              ),
              if (mediumDirectory != null)
                Text('目录：${mediumDirectory!.path}'),
              if (scan != null) ...[
                const SizedBox(height: 4),
                if (database != null) ...[
                  Text('数据库包：${database.name}'),
                  Text(
                    '原件卷：${scan.volumes.length} 个；其中与数据库包配对：'
                    '${scan.volumesMatching(database.snapshotId).length} 个',
                  ),
                ] else
                  const Text('没有找到数据库包'),
                if (scan.unmatched.isNotEmpty)
                  Text(
                    '无法识别：${scan.unmatched.map((p) => p.name).join('、')}',
                  ),
                for (final warning in scan.warnings) Text('提示：$warning'),
              ],
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(message!),
                ),
              if (controller.isBusy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
