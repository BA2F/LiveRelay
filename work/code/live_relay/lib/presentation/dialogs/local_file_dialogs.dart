import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

Future<Map<String, Object?>?> pickLocalJson({
  String title = '选择文件',
  int maxBytes = 65536,
}) async {
  final file = await FilePicker.pickFile(dialogTitle: title);
  if (file == null) return null;
  final size = await file.length();
  if (size != null && size > maxBytes) throw const FormatException('文件过大');
  final bytes = await file.readAsBytes();
  try {
    if (bytes.length > maxBytes) throw const FormatException('文件过大');
    return Map<String, Object?>.from(jsonDecode(utf8.decode(bytes)) as Map);
  } finally {
    bytes.fillRange(0, bytes.length, 0);
  }
}

Future<bool> saveLocalBytes(Uint8List bytes, String name) async {
  return await FilePicker.saveFile(fileName: name, bytes: bytes) != null;
}

/// Picks a directory to act as the device-transfer medium (USB stick, mounted
/// LAN share, or mounted WebDAV drive). Returns null when cancelled or when
/// the platform cannot provide a writable path.
Future<Directory?> pickLocalDirectory({String title = '选择介质目录'}) async {
  final path = await FilePicker.getDirectoryPath(dialogTitle: title);
  if (path == null) return null;
  return Directory(path);
}

Future<String?> askFingerprint(
  BuildContext context,
  String fingerprint,
  String name,
) async {
  final input = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text('核对$name身份'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('请通过本人、电话等独立渠道核对完整指纹；文件名和显示名称不能证明身份。'),
                const SizedBox(height: 12),
                SelectableText(fingerprint),
                const SizedBox(height: 12),
                TextField(
                  controller: input,
                  onChanged: (_) => refresh(() {}),
                  decoration: const InputDecoration(labelText: '完整输入已核对的指纹'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: input.text == fingerprint
                  ? () => Navigator.pop(context, input.text)
                  : null,
              child: const Text('已独立核对'),
            ),
          ],
        ),
      ),
    );
  } finally {
    input.dispose();
  }
}
