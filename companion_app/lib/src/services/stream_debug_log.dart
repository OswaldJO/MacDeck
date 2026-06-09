import 'package:flutter/foundation.dart';

/// Stream pipeline logs for `flutter run` (Dart only — iOS native uses NSLog / `flutter logs`).
void playniteStreamDebug(String message) {
  debugPrint('[PlayniteStream] $message');
}
