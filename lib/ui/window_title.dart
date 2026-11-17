import 'package:flutter/services.dart';

/// The window title names the repository on screen: `<folder> - Purrage`, so a
/// commit cannot land in the wrong one of several checkouts of a project.
///
/// The Windows runner owns the title (`windows/runner/flutter_window.cpp`); this
/// asks it over the `purrage/window` channel and keeps its build suffix
/// (`Purrage (dev)` in a debug build).
class WindowTitle {
  static const channel = MethodChannel('purrage/window');

  /// The last path of [repoPath], the folder name people recognise.
  static String folderOf(String repoPath) {
    final parts = repoPath.replaceAll(r'\', '/').split('/').where((part) => part.isNotEmpty);
    return parts.isEmpty ? repoPath : parts.last;
  }

  /// What the title reads for [repoPath], without the build suffix.
  static String forPath(String repoPath) => '${folderOf(repoPath)} - Purrage';

  /// Ask the runner to show [repoPath]. No runner (tests, other platforms): no-op.
  static Future<void> show(String repoPath) async {
    try {
      await channel.invokeMethod<void>('setRepository', folderOf(repoPath));
    } on MissingPluginException {
      // Not running under the Windows runner.
    } on PlatformException {
      // The title is a label; failing to set it must not become a failure.
    }
  }
}
