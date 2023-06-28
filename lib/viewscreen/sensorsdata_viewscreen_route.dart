import 'dart:collection';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:sensors_analytics_flutter_plugin/sensors_analytics_autotrack.dart';

import '../common/sensorsdata_common.dart';
import '../common/sensorsdata_logger.dart';
import '../sa_autotrack.dart' show hasCreationLocation, getLocationInfo;
import '../visualized/sensorsdata_visualized.dart';
import 'sensorsdata_viewscreen.dart';

@pragma("vm:entry-point")
class RouteViewScreenResolver {
  ///注意：
  ///TODO 另外 Navigator 可以有多个，记录的 Route 应该按照 Navigator 从属划分，不过这个会导致页面浏览逻辑变的非常复杂。
  ///TODO 暂时只支持第一个触发页面浏览的 Navigator，若检测到路由的 Navigator 不为第一个 Navigator，则忽略

  NavigatorState? navigator;

  ///维护的路由栈，包括 PopupRoute 和 PageRoute
  var _allRoutesMap = LinkedHashMap<Route, ViewScreenCache>();

  ///当存在 push 的时候记录 push 路由信息
  Route? _pushRoute;

  ///在 pop 操作的时候会返回上一个 present route
  ///通常该 Route 就是当前 Route 的前一个，不过为了在这里无法判断是否 willBePresent,
  ///所以这里会记录一下，用于作为触发页面浏览时的 Route
  Route? _lastPopPreviousRoute;

  ///所有待 pop 的路由
  var _allPopRoutes = <Route>[];
  var _allPopRoutesLength = 0;

  ///如果是 push 就需要等待 buildPage 结束，再获取页面的基本信息
  var _isBuildPageRun = false;

  ///如果是 pop 就需要等待所有的 Route 都 dispose 后，再触发页面浏览
  var _isAllRouteDisposed = false;

  ///是不是进入了 ScheduleBinding.handleDrawFrame 方法
  var _isNewFrame = false;

  BuildContext? _lastViewScreenContext; //TODO 可以通过 ViewScreenFactory lastPage 获取

  var _appBarTitle;
  var _appTitleWidget;

  static final _instance = RouteViewScreenResolver._();

  RouteViewScreenResolver._();

  factory RouteViewScreenResolver.getInstance() => _instance;

  BuildContext? get lastViewScreenContext => _lastViewScreenContext;

  void didPush(Route? route, Route? previousRoute) {
    SaLogger.p("==didPush===$route====$previousRoute");
    if (route == null) {
      return;
    }
    if (navigator == null) {
      navigator = route.navigator;
    }
    //忽略对应的路由
    if (route.navigator != this.navigator) {
      return;
    }
    ViewScreenCache cache = ViewScreenCache();
    cache.route = route;
    _allRoutesMap[route] = cache;

    if (route is PageRoute) {
      _pushRoute = route;
    }
  }

  void didPop(Route? route, Route? previousRoute) {
    SaLogger.p("==didPop===$route====$previousRoute");
    if (route == null) {
      return;
    }
    //忽略对应的路由
    if (route.navigator != this.navigator) {
      return;
    }
    _lastPopPreviousRoute = previousRoute;
    _addPopRoute(route);
  }

  void didReplace(Route? newRoute, Route? oldRoute) {
    SaLogger.p("==didReplace===$newRoute====$oldRoute");
    if (newRoute == null || oldRoute == null) {
      return;
    }
    //忽略对应的路由
    if (newRoute.navigator != this.navigator) {
      return;
    }
    ViewScreenCache cache = ViewScreenCache();
    cache.route = newRoute;
    _pushRoute = newRoute;
    _allRoutesMap[newRoute] = cache;
    _addPopRoute(oldRoute);
  }

  void didRemove(Route? route, Route? previousRoute) {
    if (route == null) {
      return;
    }
    //忽略对应的路由
    if (route.navigator != this.navigator) {
      return;
    }
    _lastPopPreviousRoute = previousRoute;
    //在 pushReplace 场景中，会触发 handlePush，但是不应该再触发 didRemove
    //所以添加的时候要判断一下
    _addPopRoute(route);
  }

  void _addPopRoute(Route route) {
    //忽略对应的路由
    if (route.navigator != this.navigator) {
      return;
    }
    if (!_allPopRoutes.contains(route)) {
      _allPopRoutes.add(route);
      _allPopRoutesLength++;
    }
  }

  /// Route 删除
  void routeDispose(Route route) {
    //忽略对应的路由
    if (route.navigator != this.navigator) {
      return;
    }
    //必须得在 _allPopRoutes 中，然后才能删除，如果不在的话，就直接从 _allRoutesMap 中删除
    if (route is PageRoute) {}
    _allPopRoutesLength--;
    if (_allPopRoutesLength == 0) {
      _isAllRouteDisposed = true;
    }

    //如果是嵌套 navigator 的场景，应该需要直接从 _allRoutesMap 中删除，因为
  }

  //TODO 如果是 Dialog，只要记录最基本的信息即可，不需要处理 buildPage 相关信息了吧
  //TODO 另外 Navigator 可以有多个，记录的 Route 应该按照 Navigator 从属划分
  ///buildPage 的时候调用该方法，用于存储一些页面的基本信息
  void buildPage(Route route, Widget? widget, BuildContext? context) {
    try {
      //忽略对应的路由
      if (route.navigator != this.navigator) {
        return;
      }
      // _pushRoute 已经屏蔽了 PopupRoute，因此这里都只是
      if (_isBuildPageRun || _pushRoute == null || _pushRoute != route) {
        return;
      }

      Widget? viewScreenWidget = widget;
      String routeWidgetName = route.runtimeType.toString();
      if ((route is CupertinoRouteTransitionMixin || route is MaterialRouteTransitionMixin) && widget is Semantics) {
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

      //填充数据
      ViewScreenCache? screenCache = _allRoutesMap[route];
      if (screenCache == null) {
        return;
      }
      screenCache.widget = viewScreenWidget;
      screenCache.buildContext = context;
      _isBuildPageRun = true;
      //从 buildPage 后的下一帧开始计算
      _isNewFrame = false;
    } catch (e, s) {
      SaLogger.e("SensorsAnalytics Exception Report: ", stackTrace: s, error: e);
    }
  }

  void beforeHandleDrawFrame() {
    _isNewFrame = true;
  }

  void afterHandleDrawFrame() {
    SaLogger.p("afterHandleDrawFrame====");
    try {
      //例如 pushReplacement、popPush
      if ((_pushRoute != null && _isBuildPageRun && _isNewFrame) && (_allPopRoutes.isNotEmpty && _isAllRouteDisposed)) {
        //1.触发 push 页面浏览
        //2.删除所有的 popRoutes
        //3.重置所有条件
        _fillViewScreenEvent(_pushRoute!, _allRoutesMap[_pushRoute]);
        _trackViewScreen(_allRoutesMap[_pushRoute]);
        _allPopRoutes.forEach((element) {
          _allRoutesMap.remove(element);
        });
        _resetViewScreen();
        return;
      }

      //例如 push
      if ((_pushRoute != null && _isBuildPageRun && _isNewFrame) && _allPopRoutes.isEmpty) {
        //1.触发 push 页面浏览
        //2.重置所有条件
        _fillViewScreenEvent(_pushRoute!, _allRoutesMap[_pushRoute]);
        _trackViewScreen(_allRoutesMap[_pushRoute]);
        _resetViewScreen();
        return;
      }

      //例如 pop、remove
      if (_pushRoute == null && (_allPopRoutes.isNotEmpty && _isAllRouteDisposed)) {
        //1._allRoutesMap 删除所有的在 _allPopRoutes 中的路由，并且 _allPopRoutes 必须要有 PageRoute，否则返回
        //2.查找 _allRoutesMap 中 willBePresent 的 Route 并触发其页面浏览
        //3.重置所有条件
        bool hasPageRoute = false;
        _allPopRoutes.forEach((element) {
          if (element is PageRoute) {
            hasPageRoute = true;
          }
          _allRoutesMap.remove(element);
        });

        if (hasPageRoute) {
          var routeList = _allRoutesMap.keys.toList();
          if (routeList.isNotEmpty) {
            int lastPopPreviousRouteIndex = -1;
            int topPageRouteIndex = -1;
            for (int index = routeList.length - 1; index >= 0; index--) {
              var route = routeList[index];
              if (route == _lastPopPreviousRoute) {
                lastPopPreviousRouteIndex = index;
              }
              if (topPageRouteIndex == -1 && route is PageRoute) {
                topPageRouteIndex = index;
              }
            }
            //如果 lastPop route 之前还有 PageRoute，就不需要触发页面浏览。典型的使用场景是 Navigator.of().remove()
            if (topPageRouteIndex > lastPopPreviousRouteIndex) {
              _resetViewScreen();
              return;
            }

            //如果 _lastPopPreviousRoute 不是 PageRoute，则可能是 PopupRoute。所以需要找到它之前的 Route
            if (_lastPopPreviousRoute! is PageRoute) {
              _lastPopPreviousRoute = routeList.lastWhere((element) => element is PageRoute, orElse: () => _lastPopPreviousRoute!);
            }

            if (_lastPopPreviousRoute is PageRoute) {
              ViewScreenCache? cache = _allRoutesMap[_lastPopPreviousRoute];
              _trackViewScreen(cache, true);
            }
          }
        }
        _resetViewScreen();
        return;
      }
      _isNewFrame = false;
    } catch (e, s) {
      //假如出现异常，也需要
      _resetViewScreen();
      SaLogger.e("SensorsAnalytics Exception Report: ", stackTrace: s, error: e);
    }
  }

  ///用于填充页面浏览的基本信息，特别是 push 的场景
  void _fillViewScreenEvent(Route route, ViewScreenCache? cache) {
    try {
      if (cache == null) {
        return;
      }
      Widget? viewScreenWidget = cache.widget;
      if (viewScreenWidget == null) {
        SaLogger.w("Not found view screen widget info.");
        return;
      }
      BuildContext? viewScreenContext = cache.buildContext;
      if (viewScreenContext == null) {
        SaLogger.w("Not found view screen build context.");
        return;
      }

      ViewScreenEvent screenEvent = ViewScreenEvent();
      cache.eventInfo = screenEvent;
      screenEvent.buildContext = viewScreenContext;

      //Fix:Flutter Modular 2.x
      if (viewScreenWidget.runtimeType.toString() == '_DisposableWidget') {
        dynamic tmp = viewScreenWidget;
        viewScreenWidget = tmp.child(viewScreenContext, null);
      }
      if (hasCreationLocation(viewScreenWidget)) {
        Map<String, dynamic> locationMap = getLocationInfo(viewScreenWidget!);
        if (locationMap["file"] != null) {
          screenEvent.fileName = locationMap["file"]!.replaceAll(locationMap["rootUrl"]!, "");
        }
        screenEvent.importUri = locationMap["importUri"];
      }
      screenEvent.routeName = route.settings.name;
      screenEvent.widgetName = viewScreenWidget?.runtimeType.toString();

      _findAppBar(viewScreenContext as Element?);
      if (_appBarTitle != null) {
        screenEvent.title = _appBarTitle;
      }

      _checkViewScreenImpl(screenEvent, viewScreenWidget);
    } catch (e, s) {
      SaLogger.e("SensorsAnalytics Exception Report: ", stackTrace: s, error: e);
    }
  }

  /// isBackViewScreen = true 表示是恢复后的路由
  void _trackViewScreen(ViewScreenCache? cache, [bool isBackViewScreen = false]) {
    if (cache == null) {
      return;
    }
    if (cache.eventInfo == null) {
      SaLogger.w(
          "_trackViewScreen 's cache.eventInfo is null, this maybe affect view screen. if you fount the viewscreen is not triggered, please contact us.");
      return;
    }
    Map<String, dynamic>? map = cache.eventInfo!.toSDKMap()!;
    SAUtils.setupLibPluginVersion(map);

    //要保证触发的先触发页面停留事件，再触发新页面的页面浏览事件
    _lastViewScreenContext = cache.buildContext;
    ViewScreenFactory.getInstance().lastRouteViewScreen = cache.eventInfo;

    //如果是返回的页面，还要判断页面中是否存在 Bottom 或 Tab 对应的页面浏览
    if (isBackViewScreen) {
      ViewScreenFactory.getInstance().trackViewScreenForBack(cache.eventInfo);
    } else {
      VisualizedStatusManager.getInstance().updatePageRefresh(false);
      ViewScreenFactory.getInstance().trackViewScreenEvent(map[r"$url"] ?? map[r"$screen_name"], map);
    }
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
    if (_appBarTitle != null || _appTitleWidget != null) {
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
        _appTitleWidget = appBar.title;
      } else {
        _appTitleWidget = appBar;
      }
      if (_appTitleWidget is Text) {
        _appBarTitle = _appTitleWidget.data;
      } else {
        _getAppBar(context);
      }
      return;
    }
    context.visitChildElements(_findAppBar);
  }

  void _getAppBar(Element element) {
    if (element.widget is AppBar) {
      _appTitleWidget = (element.widget as AppBar).title;
    }
    if (element.widget == _appTitleWidget) {
      String? result = SAUtils.resolvingWidgetContent(element, searchGestureDetector: false);
      _appBarTitle = result;
    } else {
      element.visitChildElements(_getAppBar);
    }
  }

  ///清除临时变量
  void _resetViewScreen() {
    this._pushRoute = null;
    this._appBarTitle = null;
    this._allPopRoutes.clear();
    this._allPopRoutesLength = 0;
    this._isBuildPageRun = false;
    this._isAllRouteDisposed = false;
    this._isNewFrame = false;
    this._lastPopPreviousRoute = null;
    this._appTitleWidget = null;
    this._appBarTitle = null;
    this._lastPopPreviousRoute = null;
  }
}

///用于存放每个页面、route 的对应关系，特别是 buildPage 是的对应关系
@pragma("vm:entry-point")
class ViewScreenCache {
  Route? route;

  ///Route 对应的页面信息。不一定能拿到最真实的 Widget，需要做 unwrap 操作，具体需要根据不同的实现来确定
  Widget? widget;
  BuildContext? buildContext;

  ///用于存放该 Route 对应的页面浏览实际内容
  ViewScreenEvent? eventInfo;

  @override
  String toString() {
    return 'ViewScreenCache{viewScreenRoute: $route, viewScreenWidget: $widget, viewScreenContext: $buildContext , eventInfo: ${eventInfo?.toString()}';
  }
}
