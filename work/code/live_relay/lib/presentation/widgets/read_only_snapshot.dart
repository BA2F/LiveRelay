import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/domain/entities.dart';
import '../dialogs/local_file_dialogs.dart';
import '../model_labels.dart';

/// Read-only rendering of a scoped handoff snapshot.
///
/// Shared by the recipient identity space and the local handoff view so both
/// show exactly the same authorized fields.
class ReadOnlySnapshot extends StatelessWidget {
  const ReadOnlySnapshot({super.key, required this.data});
  final Map<String, Object?> data;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 24),
      Text('来自 ${data['ownerName']} · ${data['date']}'),
      const Text('只读快照；所有者后续修改不会自动改变已交付的内容。'),
      for (final record in data['records'] as List)
        _ReadOnlyRecord(record: Map<String, Object?>.from(record as Map)),
      for (final entry in (data['originals'] as Map).entries)
        ListTile(
          leading: const Icon(Icons.attach_file),
          title: Text((entry.value as Map)['name'] as String),
          trailing: const Icon(Icons.save_alt),
          onTap: () async {
            final original = entry.value as Map;
            final bytes = Uint8List.fromList(
              base64Url.decode(
                base64Url.normalize(original['bytes'] as String),
              ),
            );
            try {
              await saveLocalBytes(
                bytes,
                (original['name'] as String).replaceAll(RegExp(r'[/\\]'), '_'),
              );
            } finally {
              bytes.fillRange(0, bytes.length, 0);
            }
          },
        ),
    ],
  );
}

class _ReadOnlyRecord extends StatefulWidget {
  const _ReadOnlyRecord({required this.record});
  final Map<String, Object?> record;
  @override
  State<_ReadOnlyRecord> createState() => _ReadOnlyRecordState();
}

class _ReadOnlyRecordState extends State<_ReadOnlyRecord> {
  bool reveal = false;
  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              record['title'] as String,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '授权级别：${VisibilityLevel.values.singleWhere((v) => v.name == record['level']).label}',
            ),
            SelectableText(record['body'] as String),
            if ((record['website'] as String? ?? '').isNotEmpty)
              Text('网址：${record['website']}'),
            if ((record['notes'] as String? ?? '').isNotEmpty)
              SelectableText('备注：${record['notes']}'),
            if (record['secret'] != null)
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      reveal ? record['secret'] as String : '••••••••',
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => reveal = !reveal),
                    icon: Icon(
                      reveal ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ],
              ),
            if ((record['history'] as List).isNotEmpty)
              ExpansionTile(
                title: const Text('已单独授权的修订历史'),
                children: [
                  for (final revision in record['history'] as List)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        const JsonEncoder.withIndent('  ').convert({
                          ...revision as Map,
                          if ((revision).containsKey('secret') && !reveal)
                            'secret': '••••••••',
                        }),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
