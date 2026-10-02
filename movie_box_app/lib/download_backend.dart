import 'package:background_downloader/background_downloader.dart' as native;
import 'package:flutter/widgets.dart';

import 'api.dart';
import 'download_probe.dart';

const movieDownloadGroup = 'moviebox.downloads.v1';

/// Injectable boundary; production transfers always use the platform worker.
abstract class DownloadBackend {
  Future<void> initialize(void Function(native.TaskUpdate) onUpdate);
  Future<void> reconcile();
  Future<List<native.TaskRecord>> records();
  Future<List<native.Task>> pending();
  Future<bool> enqueue(native.DownloadTask task);
  Future<bool> pause(native.DownloadTask task);
  Future<bool> resume(native.DownloadTask task);
  Future<bool> cancel(String id);
  Future<void> requestNotifications();
  Future<DownloadMetadata> probe(String url, Map<String, String> headers) =>
      DownloadMetadataProbe().probe(url, headers);
  void dispose();
}

class NativeDownloadBackend extends DownloadBackend {
  late final native.FileDownloader _downloader = native.FileDownloader();
  final Future<native.PermissionStatus> Function()? notificationStatus;
  final Future<native.PermissionStatus> Function()?
  requestNotificationPermission;
  final bool Function()? isForeground;

  NativeDownloadBackend({
    this.notificationStatus,
    this.requestNotificationPermission,
    this.isForeground,
  });

  @override
  Future<void> initialize(void Function(native.TaskUpdate) onUpdate) async {
    _downloader.registerCallbacks(
      group: movieDownloadGroup,
      taskStatusCallback: onUpdate,
      taskProgressCallback: onUpdate,
    );
    _downloader.configureNotificationForGroup(
      movieDownloadGroup,
      running: const native.TaskNotification(
        '{displayName}',
        '{progress} • {networkSpeed} • {timeRemaining} remaining',
      ),
      complete: const native.TaskNotification(
        '{displayName}',
        'Download complete',
      ),
      error: const native.TaskNotification(
        '{displayName}',
        'Download failed. Open MovieBox to retry.',
      ),
      paused: const native.TaskNotification('{displayName}', 'Download paused'),
      canceled: const native.TaskNotification(
        '{displayName}',
        'Download cancelled',
      ),
      progressBar: true,
      tapOpensFile: false,
    );
    await _downloader.configure(
      androidConfig: [
        (native.Config.runInForeground, true),
        (native.Config.useCacheDir, native.Config.never),
      ],
    );
    await _downloader.trackTasksInGroup(
      movieDownloadGroup,
      markDownloadedComplete: false,
    );
    await reconcile();
  }

  @override
  Future<void> reconcile() => _downloader.resumeFromBackground();

  @override
  Future<List<native.TaskRecord>> records() =>
      _downloader.database.allRecords(group: movieDownloadGroup);

  @override
  Future<List<native.Task>> pending() =>
      _downloader.allTasks(group: movieDownloadGroup);

  @override
  Future<bool> enqueue(native.DownloadTask task) => _downloader.enqueue(task);

  @override
  Future<bool> pause(native.DownloadTask task) => _downloader.pause(task);

  @override
  Future<bool> resume(native.DownloadTask task) => _downloader.resume(task);

  @override
  Future<bool> cancel(String id) => _downloader.cancelTaskWithId(id);

  @override
  Future<void> requestNotifications() async {
    var status =
        await (notificationStatus?.call() ??
            _downloader.permissions.status(
              native.PermissionType.notifications,
            ));
    if (status != native.PermissionStatus.granted &&
        (isForeground?.call() ??
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed)) {
      status =
          await (requestNotificationPermission?.call() ??
              _downloader.permissions.request(
                native.PermissionType.notifications,
              ));
    }
    if (status != native.PermissionStatus.granted) {
      throw ApiException(
        'Allow notifications in Android Settings to run background downloads.',
      );
    }
  }

  @override
  void dispose() => _downloader.unregisterCallbacks(group: movieDownloadGroup);
}
