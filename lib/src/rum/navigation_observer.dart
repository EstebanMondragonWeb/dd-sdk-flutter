// Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2019-2022 Datadog, Inc.

import 'package:flutter/material.dart';

import '../../datadog_sdk.dart';

class RumViewInfo {
  final String name;
  final String? path;
  final String? service;
  final Map<String, dynamic> attributes;

  RumViewInfo({
    required this.name,
    this.path,
    this.service,
    this.attributes = const {},
  });
}

typedef ViewInfoExtractor = RumViewInfo? Function(Route route);

RumViewInfo? defaultViewInfoExtractor(Route route) {
  if (route is PageRoute) {
    var name = route.settings.name;
    if (name != null) {
      return RumViewInfo(name: name);
    }
  }

  return null;
}

/// This class can be added to a MaterialApp to automatically start and stop RUM
/// views, provided you are using named routes with methods like
/// [Navigator.pushNamed], or supplying route names through [RouteSettings] when
/// using [Navigator.push].
///
/// Alternately, the DatadogNavigationObserver can also be used in conjunction
/// with [DatadogNavigationObserverProvider] and [DatadogRouteAwareMixin] to
/// automatically start and stop RUM views on widgets that use the mixin.
///
/// If you want more control over the names and attributes that are sent to RUM,
/// you can supply a function, [ViewInfoExtractor], to [viewInfoExtractor]. This
/// function is called with the current Route, and can be used to supply a
/// different name, path, or extra attributes to any route.
class DatadogNavigationObserver extends RouteObserver<ModalRoute<dynamic>> {
  final ViewInfoExtractor viewInfoExtractor;
  final DatadogSdk datadogSdk;

  DatadogNavigationObserver({
    required this.datadogSdk,
    this.viewInfoExtractor = defaultViewInfoExtractor,
  });

  Future<void> _sendScreenView(Route? newRoute, Route? oldRoute) async {
    final oldRouteInfo = oldRoute != null ? viewInfoExtractor(oldRoute) : null;
    final newRouteInfo = newRoute != null ? viewInfoExtractor(newRoute) : null;

    if (oldRouteInfo != null) {
      await datadogSdk.rum?.stopView(oldRouteInfo.name);
    }
    if (newRouteInfo != null) {
      await datadogSdk.rum
          ?.startView(newRouteInfo.name, null, newRouteInfo.attributes);
    }
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    _sendScreenView(route, previousRoute);
    super.didPush(route, previousRoute);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    _sendScreenView(newRoute, oldRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);

    // On pop, the "previous" route is now the new roue.
    _sendScreenView(previousRoute, route);
  }
}

/// The DatadogRouteAwareMixin can be used to supply names and additional
/// attributes to RUM views as an alternative to supplying a [ViewInfoExtractor]
/// to [DatadogNavigationObserver], supplying a name when creating the route, or
/// using named routes.
///
/// Usage:
///
/// ```
/// class ViewWidget extends StatefulWidget {
///   const ViewWidget({Key? key}) : super(key: key);
///
///   @override
///   _ViewWidgetState createState() => _ViewWidgetState();
/// }
///
/// class _ViewWidgetState extends State<ViewWidget>
///     with RouteAware, DatadogRouteAwareMixin {
///   // ...
/// }
/// ```
///
/// By default, DatadogRouteAwareMixin will use the name of its parent Widget as
/// the name of the route. You can override this by overriding the [rumViewInfo]
/// getter, as well as supply additional properties about the view.
///
/// Note: this should not be used with named routes. By design, the Mixin checks
/// if a name was already assigned to its route and will not send any tracking
/// events in that case
mixin DatadogRouteAwareMixin<T extends StatefulWidget> on State<T>, RouteAware {
  DatadogNavigationObserver? _routeObserver;

  /// Override this method to supply extra view info for this view through the
  /// [RumViewInfo] class. By default, it returns the name of the parent Widget
  /// as the name of the view.
  RumViewInfo get rumViewInfo {
    return RumViewInfo(name: widget.toString());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _routeObserver = DatadogNavigationObserverProvider.of(context)?.navObserver;
    final route = ModalRoute.of(context);
    if (route != null) {
      _routeObserver?.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _routeObserver?.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPush() {
    _startView();
    super.didPush();
  }

  @override
  void didPop() {
    super.didPop();
    _stopView();
  }

  @override
  void didPushNext() {
    super.didPushNext();
    _stopView();
  }

  @override
  void didPopNext() {
    _startView();
    super.didPopNext();
  }

  void _startView() {
    if (_routeObserver != null) {
      final info = rumViewInfo;
      _routeObserver?.datadogSdk.rum
          ?.startView(info.name, null, info.attributes);
    }
  }

  void _stopView() {
    if (_routeObserver != null) {
      final info = rumViewInfo;
      _routeObserver?.datadogSdk.rum?.stopView(info.name);
    }
  }
}

/// This can be used to provide the DatadogNavigationObserver to other classes that need it, specifically,
/// if you want to use the [DatadogRouteAwareMixin], you must use this provider.
///
/// The provider should be placed above your MaterialApp or application route.
/// ```
/// void main() {
///   // Other setup code
///   final observer = DatadogNavigationObserver(datadogSdk: DatadogSdk.instance);
///   runApp(DatadogRouteAwareMixin(
///     navObserver: observer,
///     child: MaterialApp(
///       navigatorObservers: [observer],
///       // other initialization
///     ),
///   );
/// }
/// ```
///
/// See also [DatadogRouteAwareMixin]
class DatadogNavigationObserverProvider extends InheritedWidget {
  final DatadogNavigationObserver navObserver;

  const DatadogNavigationObserverProvider({
    Key? key,
    required this.navObserver,
    required Widget child,
  }) : super(key: key, child: child);

  @override
  bool updateShouldNotify(
          covariant DatadogNavigationObserverProvider oldWidget) =>
      navObserver != oldWidget.navObserver;

  static DatadogNavigationObserverProvider? of(BuildContext context) {
    final result = context.dependOnInheritedWidgetOfExactType<
        DatadogNavigationObserverProvider>();
    return result;
  }
}
