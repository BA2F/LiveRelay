import 'package:flutter/material.dart';

import '../../application/device_capabilities.dart';

Future<void> showCapabilityMessage(
  BuildContext context,
  String title,
  FeatureCapability capability,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: Text(capability.message),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('知道了'),
      ),
    ],
  ),
);
