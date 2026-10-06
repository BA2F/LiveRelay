import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../application/app_controller.dart';
import '../../application/device_capabilities.dart';
import '../dialogs/capability_dialog.dart';
import '../../core/domain/entities.dart';
import '../design_system/atoms.dart';
import '../dialogs/ai_privacy_dialogs.dart';
import '../dialogs/card_dialogs.dart';
import '../dialogs/media_viewer.dart';
import '../widgets/local_pdf_preview.dart';

String mediaLabel(BlobMediaKind kind) => switch (kind) {
  BlobMediaKind.image => '照片',
  BlobMediaKind.audio => '录音',
  BlobMediaKind.video => '录像',
  BlobMediaKind.document => '文档',
  BlobMediaKind.other => '其他',
};
IconData mediaIcon(BlobMediaKind kind) => switch (kind) {
  BlobMediaKind.image => Icons.image_outlined,
  BlobMediaKind.audio => Icons.audio_file_outlined,
  BlobMediaKind.video => Icons.video_file_outlined,
  _ => Icons.insert_drive_file_outlined,
};

class OriginalsPage extends StatefulWidget {
  const OriginalsPage({super.key});
  @override
  State<OriginalsPage> createState() => _OriginalsPageState();
}

class _OriginalsPageState extends State<OriginalsPage> {
  final _search = TextEditingController();
  BlobMediaKind? _kind;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final query = _search.text.trim().toLowerCase();
    final visible = controller.blobs
        .where(
          (b) =>
              (_kind == null || _kind == b.mediaKind) &&
              '${b.originalName} ${b.ocrText ?? ''}'.toLowerCase().contains(
                query,
              ),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('全部原件')),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Semantics(
              label: '搜索原件',
              child: SearchField(
                controller: _search,
                hintText: '搜索文件名或识别文字',
                leading: const Icon(Icons.search),
                onChanged: (_) => setState(() {}),
                trailing: [
                  if (query.isNotEmpty)
                    IconButton(
                      tooltip: '清除搜索',
                      onPressed: () => setState(_search.clear),
                      icon: const Icon(Icons.clear),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilterChip(
                  label: const Text('全部'),
                  selected: _kind == null,
                  onSelected: (_) => setState(() => _kind = null),
                ),
                for (final kind in BlobMediaKind.values)
                  FilterChip(
                    label: Text(mediaLabel(kind)),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (controller.lastError != null)
              ErrorBanner(controller.lastError!),
            if (visible.isEmpty)
              EmptyState(
                icon: Icons.folder_open,
                title: controller.blobs.isEmpty
                    ? '还没有原件'
                    : query.isNotEmpty
                    ? '没有匹配的原件'
                    : '此类型暂无原件',
                message: controller.blobs.isEmpty
                    ? '在记录页拍照、录音或导入文件，原件会加密保存在这里。'
                    : '调整关键词或类型，已保存的原件仍在资料库中。',
              ),
            for (final blob in visible)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(mediaIcon(blob.mediaKind)),
                title: Text(blob.originalName),
                subtitle: Text(
                  '${mediaLabel(blob.mediaKind)} · ${DateFormat('yyyy-MM-dd').format(blob.createdAt.toLocal())} · ${blob.ocrText == null ? '可手工整理' : '已有识别文字'}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openOriginalWorkspace(context, controller, blob),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> openOriginalWorkspace(
  BuildContext context,
  AppController controller,
  VaultBlob blob,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => _OriginalWorkspace(controller: controller, blob: blob),
  ),
);

class _OriginalWorkspace extends StatefulWidget {
  const _OriginalWorkspace({required this.controller, required this.blob});
  final AppController controller;
  final VaultBlob blob;
  @override
  State<_OriginalWorkspace> createState() => _OriginalWorkspaceState();
}

class _OriginalWorkspaceState extends State<_OriginalWorkspace> {
  Uint8List? _image;
  String? _error;
  late Future<List<LifeCard>> _linked = widget.controller.cardsForBlob(
    widget.blob.id,
  );
  @override
  void initState() {
    super.initState();
    if (widget.blob.mediaKind == BlobMediaKind.image) _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await widget.controller.readOriginal(widget.blob.id);
      if (!mounted) {
        bytes.fillRange(0, bytes.length, 0);
        return;
      }
      setState(() => _image = bytes);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _image?.fillRange(0, _image!.length, 0);
    super.dispose();
  }

  void _reloadLinked() {
    if (mounted) {
      setState(() {
        _linked = widget.controller.cardsForBlob(widget.blob.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final blob = controller.blobs.firstWhere(
        (b) => b.id == widget.blob.id,
        orElse: () => widget.blob,
      );
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: Text(blob.originalName),
            bottom: const TabBar(
              tabs: [
                Tab(text: '查看原件'),
                Tab(text: '整理内容'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('${mediaLabel(blob.mediaKind)} · 已加密保存在本机'),
                  const SizedBox(height: 12),
                  if (_error != null) ErrorBanner(_error!),
                  if (blob.mediaKind == BlobMediaKind.image && _error == null)
                    _image == null
                        ? const LinearProgressIndicator()
                        : Semantics(
                            label: '${blob.originalName} 原件图像',
                            child: Image.memory(
                              _image!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Text('图像格式无法预览'),
                            ),
                          ),
                  if (Platform.isLinux &&
                      LocalPdfPreview.supports(
                        blob.originalName,
                        blob.mimeType,
                      ))
                    LocalPdfPreview(
                      session: controller,
                      name: blob.originalName,
                      readBytes: () => controller.readOriginal(blob.id),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () =>
                        showEncryptedOriginal(context, controller, blob),
                    icon: Icon(mediaIcon(blob.mediaKind)),
                    label: Text(
                      blob.mediaKind == BlobMediaKind.image
                          ? '放大查看原件'
                          : '播放 / 查看原件',
                    ),
                  ),
                ],
              ),
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('可直接手工填写关联说明。识别或 AI 整理生成的内容都需要本人核对。'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.edit_note),
                    label: const Text('手工整理关联说明'),
                    onPressed: controller.isBusy
                        ? null
                        : () async {
                            await showCardEditor(
                              context,
                              controller,
                              sourceBlobId: blob.id,
                              initialContent: blob.ocrText,
                            );
                            _reloadLinked();
                          },
                  ),
                  if (blob.mediaKind == BlobMediaKind.image)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.document_scanner_outlined),
                      label: Text(
                        blob.ocrText == null ? '在本机识别文字' : '重新识别并生成草稿',
                      ),
                      onPressed: controller.isBusy
                          ? null
                          : () {
                              final capability = controller.capability(
                                AppFeature.ocr,
                              );
                              if (!capability.isAvailable) {
                                showCapabilityMessage(
                                  context,
                                  '识别文字',
                                  capability,
                                );
                                return;
                              }
                              runUiAction(context, () async {
                                await controller.runOcr(blob.id);
                                _reloadLinked();
                              }, success: '识别文字已保存为待整理草稿');
                            },
                    ),
                  if (blob.ocrText != null) ...[
                    ExpansionTile(
                      title: const Text('查看识别文字'),
                      children: [SelectableText(blob.ocrText!)],
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.privacy_tip_outlined),
                      label: const Text('检查 AI 外发内容'),
                      onPressed: controller.isBusy
                          ? null
                          : () async {
                              await showAiPrivacyWorkspace(
                                context,
                                controller,
                                blob,
                              );
                              _reloadLinked();
                            },
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    '关联卡片与草稿',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  FutureBuilder<List<LifeCard>>(
                    future: _linked,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return ErrorBanner('关联卡片读取失败：${snapshot.error}');
                      }
                      if (!snapshot.hasData) {
                        return const LinearProgressIndicator();
                      }
                      return Column(
                        children: snapshot.data!
                            .map(
                              (card) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(card.title),
                                subtitle: Text(
                                  card.isDraft ? '待整理 · 需要本人确认' : '本人已确认',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () async {
                                  await showCardDetails(
                                    context,
                                    controller,
                                    card,
                                  );
                                  _reloadLinked();
                                },
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
