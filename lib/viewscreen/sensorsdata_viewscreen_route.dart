import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:sensors_analytics_flutter_plugin/sensors_analytics_autotrack.dart';
import 'package:sensors_analytics_flutter_plugin/sensors_analytics_flutter_plugin.dart';

import '../common/sensorsdata_common.dart';
import '../common/sensorsdata_logger.dart';
import '../sa_autotrack.dart' show hasCreationLocation, getLocationInfo;
import '../visualized/sensorsdata_visualized.dart';
import 'sensorsdata_viewscreen.dart';

@pragma("vm:entry-point")
class RouteViewScreenResolver {
  ///用于存放对应的路由和页面浏览事件
  var _viewScreenCache = <Route?, ViewScreenCache>{};

  ///例如返回操作，需要触发上一个页面的页面浏览，保存与 Route 与页面浏览事件的对应关系
  var _routeViewScreenMap = <Route?, ViewScreenEvent>{};

  ///临时结构，用于记录最后一个路由的前一个路由
  LastRoute? _lastRouteStatus;
  bool _isReplaceRoute = false;

  ///route 生命周期回调的时候记录路由信息，然后在 buildPage 之后获取 page 信息
  Route? _tryRoute;
  BuildContext? _lastViewScreenContext;//TODO 可以通过 ViewScreenFactory lastPage 获取
  Widget? _lastViewScreenWidget;

  var appBarTitle;
  var appTitleWidget;

  static final _instance = RouteViewScreenResolver._();

  RouteViewScreenResolver._();

  factory RouteViewScreenResolver.getInstance() => _instance;

  BuildContext? get lastViewScreenContext => _lastViewScreenContext;

  Widget? get lastViewScreenWidget => _lastViewScreenWidget;

  void didPush(Route? route, Route? previousRoute) {
    SaLogger.p("==didpush===$route====$previousRoute");
    if (_lastRouteStatus != null && _lastRouteStatus!.routeStatus == RouteStatus.pop) {
      _routeViewScreenMap.remove(_lastRouteStatus!.route);
      SaLogger.p("delete lastRoute=====$_lastRouteStatus");
    }
    _lastRouteStatus = null;
    _tryRoute = route;
    //push 情况需要直接触发新的页面浏览事件，是否要考虑多次 push 的情况
    //_printViewScreenMap();
  }

  void didPop(Route? route, Route? previousRoute) {
    SaLogger.p("==didPop===$route====$previousRoute");
    if (_lastRouteStatus != null) {
      _routeViewScreenMap.remove(_lastRouteStatus!.route);
    }

    _lastRouteStatus = LastRoute();
    _lastRouteStatus!.routeStatus = RouteStatus.pop;
    _lastRouteStatus!.route = route;
    _lastRouteStatus!.previousRoute = previousRoute;

    //_printViewScreenMap();
    //1.如果是 popAndPush，此处应该只是移除
    //2.如果是 popUntil，此处应该只记录最后一个
  }

  void didReplace(Route? newRoute, Route? oldRoute) {
    SaLogger.p("==didReplace===$newRoute====$oldRoute");
    _routeViewScreenMap.remove(oldRoute);
    _tryRoute = newRoute;
    _isReplaceRoute = true;
    // replace 需要直接触发新的页面路由的页面浏览事件
    // _printViewScreenMap();
  }

  void didRemove(Route? route, Route? previousRoute) {
    if (!_isReplaceRoute) {
      SaLogger.p("==didRemove===$route====$previousRoute===$_isReplaceRoute");
      //此处要删除 route 中的所有路由，不用管 previousRoute
      _routeViewScreenMap.remove(route);
      //_printViewScreenMap();
    }
  }

  void popRemove(Route route, Route previousRoute) {
    //[优化]需要处理返回的时候页面浏览
  }

  void pushReplace(Route route, Route previousRoute) {}

  void persistentFrameCallback(Duration timeStamp) {
    //SaLogger.p("persistent frame callback====");
    //在此处恢复状态为 none
    if (_lastRouteStatus != null && _lastRouteStatus!.routeStatus == RouteStatus.pop) {
      _routeViewScreenMap.remove(_lastRouteStatus!.route);
      ViewScreenEvent? screenEvent = _routeViewScreenMap[_lastRouteStatus!.previousRoute];
      if (screenEvent != null) {
        ViewScreenFactory.getInstance().trackViewScreen(screenEvent);
        _lastViewScreenContext = screenEvent.buildContext;
        ViewScreenFactory.getInstance().lastRouteViewScreen = screenEvent;
        _resetViewScreen();
      }
    }
    _lastRouteStatus = null;
    _isReplaceRoute = false;

    _internalUpdateRoute();
  }

  void _internalUpdateRoute() {
    //将调用 buildPage 产生的缓存的数据清空，并触发页面浏览事件
    _viewScreenCache.removeWhere((Route? route, ViewScreenCache screenCache) {
      if (route != null && screenCache.viewScreenContext != null) {
        appTitleWidget = null;
        appBarTitle = null;

        Route? viewScreenRoute = screenCache.viewScreenRoute;
        Widget? viewScreenWidget = screenCache.viewScreenWidget;
        BuildContext? viewScreenContext = screenCache.viewScreenContext;

        //Fix:Flutter Modular 2.x
        if (viewScreenWidget.runtimeType.toString() == '_DisposableWidget') {
          dynamic tmp = viewScreenWidget;
          viewScreenWidget = tmp.child(viewScreenContext, null);
        }
        ViewScreenEvent screenEvent = ViewScreenEvent();
        screenEvent.buildContext = viewScreenContext;
        if (hasCreationLocation(viewScreenWidget)) {
          Map<String, dynamic> locationMap = getLocationInfo(viewScreenWidget!);
          if (locationMap["file"] != null) {
            screenEvent.fileName = locationMap["file"]!.replaceAll(locationMap["rootUrl"]!, "");
          }
          screenEvent.importUri = locationMap["importUri"];
        }

        _findAppBar(viewScreenContext as Element?);
        if (appBarTitle != null) {
          screenEvent.title = appBarTitle;
        }
        screenEvent.routeName = viewScreenRoute?.settings?.name;
        screenEvent.widgetName = viewScreenWidget?.runtimeType.toString();
        //需要确认 screenEvent page file url 如何获取
        _checkViewScreenImpl(screenEvent, viewScreenWidget);
        Map<String, dynamic>? map = screenEvent.toSDKMap()!;
        SAUtils.setupLibPluginVersion(map);
        VisualizedStatusManager.getInstance().updatePageRefresh(false);
        SensorsAnalyticsFlutterPlugin.trackViewScreen(map[r"$url"] ?? map[r"$screen_name"], map);
        _routeViewScreenMap[viewScreenRoute] = screenEvent;
        ViewScreenFactory.getInstance().lastRouteViewScreen = screenEvent;
        //TODO 这里要注意一下，需要处理，可以将其放在 resetViewScreen() 方法中 _tabIndexMap.clear();
        _resetViewScreen();
      }
      return true;
    });
  }

  ///buildPage 的时候调用该方法，用于存储一些页面的基本信息
  void buildPage(Route route, Widget? widget, BuildContext? context) {
    if (_tryRoute == null || _tryRoute != route) {
      return;
    }

    Widget? viewScreenWidget = widget;
    // 如果是对话框路由
    // TODO 应该获取第一个自己创建的 Widget
    String routeWidgetName = route.runtimeType.toString();
    if (route is PopupRoute) {
      if (routeWidgetName.startsWith('CupertinoDialogRoute<') ||
          routeWidgetName.startsWith('CupertinoModalPopupRoute<') ||
          routeWidgetName.startsWith('_CupertinoModalPopupRoute<')) {
        if (widget is Semantics) {
          viewScreenWidget = widget.child;
        } else {
          viewScreenWidget = widget;
        }
      }
      //对于 RawDialogRoute 比较麻烦，其内部做了很多的 wrap，所以要拿到真实的 Widget，就需要一步一步来操作
      else {
        if ((routeWidgetName.startsWith('DialogRoute<') ||
                routeWidgetName.startsWith('_DialogRoute<') ||
                routeWidgetName.startsWith('RawDialogRoute<')) &&
            widget is Semantics) {
          try {
            dynamic tmpWidget = widget.child;
            if (tmpWidget is SafeArea) {
              tmpWidget = tmpWidget.child;
            }
            //wrap 情况
            if (tmpWidget.runtimeType.toString() == '_CaptureAll') {
              tmpWidget = tmpWidget.child;
            }
            //此时应该是 builder
            if (tmpWidget is Builder) {
              tmpWidget = tmpWidget.build(context!);
            }
            viewScreenWidget = tmpWidget;
          } catch (e, s) {
            viewScreenWidget = widget;
          }
        } else {
          viewScreenWidget = widget;
        }
      }
    }
    //因为 aspectd  AOP 处理 PageRouteBuilder 存在问题，这里做一个判断，将逻辑放在这里
    else if ((route is CupertinoRouteTransitionMixin || route is MaterialRouteTransitionMixin) && widget is Semantics) {
      viewScreenWidget = widget.child;
    } else {
      if (routeWidgetName.startsWith("GetPageRoute<")) {
        Map<String, dynamic> locationInfoMap = getLocationInfo(widget!);
        if (locationInfoMap["isProjectRoot"]) {
          viewScreenWidget = widget;
        } else if (widget is Semantics) {
          viewScreenWidget = widget.child;
        } else {
          viewScreenWidget = widget;
        }
      } else {
        viewScreenWidget = widget;
      }
    }

    ViewScreenCache screenCache = ViewScreenCache();
    screenCache.viewScreenWidget = viewScreenWidget;
    screenCache.viewScreenRoute = _tryRoute;
    screenCache.viewScreenContext = context;
    _viewScreenCache[_tryRoute] = screenCache;
    _tryRoute = null;
    _lastViewScreenContext = context;
    _lastViewScreenWidget = viewScreenWidget;
  }

  ///判断页面是否实现了 ISensorsDataViewScreen 接口
  void _checkViewScreenImpl(ViewScreenEvent viewScreenEvent, Widget? viewScreenWidget) {
    if (viewScreenWidget != null && viewScreenWidget is ISensorsDataViewScreen) {
      ISensorsDataViewScreen sensorsDataViewScreen = viewScreenWidget as ISensorsDataViewScreen;
      try {
        viewScreenEvent.viewScreenName = sensorsDataViewScreen.viewScreenName;
      } catch (e) {
        viewScreenEvent.viewScreenName = null;
      }
      try {
        viewScreenEvent.viewScreenTitle = sensorsDataViewScreen.viewScreenTitle;
      } catch (e) {
        viewScreenEvent.viewScreenTitle = null;
      }
      try {
        viewScreenEvent.viewScreenUrl = sensorsDataViewScreen.viewScreenUrl;
      } catch (e) {
        viewScreenEvent.viewScreenUrl = null;
      }
      try {
        viewScreenEvent.trackProperties = sensorsDataViewScreen.trackProperties;
      } catch (e) {
        viewScreenEvent.trackProperties = null;
      }
    }
  }

  ///根据 Element 查找 Scaffold，再获取 AppBar 中的 title 信息
  void _findAppBar(Element? context) {
    if (appBarTitle != null || appTitleWidget != null) {
      return;
    }
    if (context!.widget is Scaffold) {
      Scaffold scaffold = context.widget as Scaffold;
      PreferredSizeWidget? appBar = scaffold.appBar;
      //如果没有 appbar，就直接返回，对应的title就是空
      if (appBar == null) {
        return;
      }
      if (appBar is AppBar) {
        appTitleWidget = appBar.title;
      } else {
        appTitleWidget = appBar;
      }
      if (appTitleWidget is Text) {
        appBarTitle = appTitleWidget.data;
      } else {
        _getAppBar(context);
      }
      return;
    }
    context.visitChildElements(_findAppBar);
  }

  void _getAppBar(Element element) {
    if (element.widget is AppBar) {
      appTitleWidget = (element.widget as AppBar).title;
    }
    if (element.widget == appTitleWidget) {
      String? result = SAUtils.resolvingWidgetContent(element, searchGestureDetector: false);
      appBarTitle = result;
    } else {
      element.visitChildElements(_getAppBar);
    }
  }

  ///清除临时变量
  void _resetViewScreen() {
    this._tryRoute = null;
    this.appBarTitle = null;
  }
}

/// 用于记录路由状态，例如调用 popUntil 方法，就是表示
enum RouteStatus { pop_until, pop, push, pop_and_push, push_and_remove_until, push_replacement, none }

/// 用来记录最后一个路由的状态，记录中间路由状态
class LastRoute {
  Route? route;
  Route? previousRoute;
  RouteStatus routeStatus = RouteStatus.none;
}

///用于存放每个页面、route 的对应关系，特别是 buildPage 是的对应关系
@pragma("vm:entry-point")
class ViewScreenCache {
  Route? viewScreenRoute;
  Widget? viewScreenWidget;
  BuildContext? viewScreenContext;

  @override
  String toString() {
    return 'ViewScreenCache{viewScreenRoute: $viewScreenRoute, viewScreenWidget: $viewScreenWidget, viewScreenContext: $viewScreenContext}';
  }
}
