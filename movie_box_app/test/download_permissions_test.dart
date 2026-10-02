import 'package:background_downloader/background_downloader.dart' as native;
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_box_app/api.dart';
import 'package:movie_box_app/download_backend.dart';

class FakePermissions {
  native.PermissionStatus current = native.PermissionStatus.denied;
  native.PermissionStatus result = native.PermissionStatus.denied;
  int requests = 0;
  Future<native.PermissionStatus> status(native.PermissionType type) async =>
      current;
  Future<native.PermissionStatus> request(native.PermissionType type) async {
    requests++;
    return result;
  }

  Future<bool> shouldShowRationale(native.PermissionType type) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Denied notification result blocks background downloads with Settings action', () async {
    final permissions = FakePermissions();
    final backend = NativeDownloadBackend(
      notificationStatus: () =>
          permissions.status(native.PermissionType.notifications),
      requestNotificationPermission: () =>
          permissions.request(native.PermissionType.notifications),
      isForeground: () => true,
    );
    await expectLater(
      backend.requestNotifications(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'action',
          'Allow notifications in Android Settings to run background downloads.',
        ),
      ),
    );
    expect(permissions.requests, 1);
  });
  test(
    'Absent foreground never requests permissions and denial is recoverable',
    () async {
      final permissions = FakePermissions();
      final backend = NativeDownloadBackend(
        notificationStatus: () =>
            permissions.status(native.PermissionType.notifications),
        requestNotificationPermission: () =>
            permissions.request(native.PermissionType.notifications),
        isForeground: () => false,
      );
      await expectLater(
        backend.requestNotifications(),
        throwsA(isA<ApiException>()),
      );
      expect(permissions.requests, 0);
      permissions.current = native.PermissionStatus.granted;
      await backend.requestNotifications();
      expect(permissions.requests, 0);
    },
  );
  test(
    'Granted request proceeds but authorization is checked on every invocation',
    () async {
      final permissions = FakePermissions()
        ..result = native.PermissionStatus.granted;
      final backend = NativeDownloadBackend(
        notificationStatus: () =>
            permissions.status(native.PermissionType.notifications),
        requestNotificationPermission: () =>
            permissions.request(native.PermissionType.notifications),
        isForeground: () => true,
      );
      await backend.requestNotifications();
      permissions.result = native.PermissionStatus.denied;
      await expectLater(
        backend.requestNotifications(),
        throwsA(isA<ApiException>()),
      );
      expect(permissions.requests, 2);
    },
  );
}
