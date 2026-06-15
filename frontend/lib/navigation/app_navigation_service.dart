import 'package:flutter/material.dart';

/* Global navigator + messenger keys so any code can change screens or show
   a snackbar without a BuildContext. */
class AppNavigationService {
  AppNavigationService._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static NavigatorState? get navigator => navigatorKey.currentState;

  static BuildContext? get context => navigatorKey.currentContext;

  static Future<T?> pushNamed<T>(String routeName, {Object? arguments}) {
    return navigatorKey.currentState!.pushNamed<T>(routeName, arguments: arguments);
  }

  static Future<T?> pushReplacementNamed<T, TO>(String routeName,
      {Object? arguments, TO? result}) {
    return navigatorKey.currentState!
        .pushReplacementNamed<T, TO>(routeName, arguments: arguments, result: result);
  }

  static void pop<T>([T? result]) {
    navigatorKey.currentState?.pop<T>(result);
  }
}
