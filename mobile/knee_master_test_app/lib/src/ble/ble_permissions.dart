import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

class BlePermissionsResult {
  const BlePermissionsResult({
    required this.granted,
    required this.missingPermissions,
  });

  final bool granted;
  final List<Permission> missingPermissions;
}

class BlePermissions {
  Future<BlePermissionsResult> requestForBle() async {
    if (!Platform.isAndroid) {
      return const BlePermissionsResult(granted: true, missingPermissions: []);
    }

    final permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];

    final statuses = await permissions.request();
    final missing = statuses.entries
        .where((entry) => !entry.value.isGranted)
        .map((entry) => entry.key)
        .toList(growable: false);

    return BlePermissionsResult(
      granted: missing.isEmpty,
      missingPermissions: missing,
    );
  }
}
