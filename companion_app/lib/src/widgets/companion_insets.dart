import 'dart:io';

import 'package:flutter/material.dart';

/// Android system bar insets (nav bar / gesture area). iOS is unchanged.
abstract final class CompanionInsets {
  static bool get _android => Platform.isAndroid;

  /// Horizontal padding for tab content when the 3-button nav bar is on the side.
  static EdgeInsets contentSides(BuildContext context) {
    if (!_android) return EdgeInsets.zero;
    final padding = MediaQuery.paddingOf(context);
    return EdgeInsets.only(left: padding.left, right: padding.right);
  }

  /// Standard list/tab padding including Android bottom nav inset.
  static EdgeInsets listPadding(BuildContext context, {double base = 16}) {
    if (!_android) {
      return EdgeInsets.all(base);
    }
    final padding = MediaQuery.paddingOf(context);
    return EdgeInsets.fromLTRB(
      base + padding.left,
      base,
      base + padding.right,
      base + padding.bottom,
    );
  }

  /// Bottom padding for modal bottom sheets (above Android nav bar).
  static double sheetBottom(BuildContext context, {double extra = 24}) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    if (!_android) return keyboard + extra;
    return keyboard + MediaQuery.paddingOf(context).bottom + extra;
  }

  /// Wrap the bottom [NavigationBar] so it sits above the Android system nav.
  static Widget wrapNavigationBar({required Widget child}) {
    if (!_android) return child;
    return SafeArea(top: false, left: false, right: false, child: child);
  }
}
