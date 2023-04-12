import 'package:flutter/widgets.dart';
import 'package:sensors_analytics_flutter_plugin/sensors_analytics_flutter_plugin.dart';

import '../common/sensorsdata_common.dart';
import '../common/sensorsdata_logger.dart';
import '../config/sensorsdata_autotrack_config.dart';
import '../visualized/sensorsdata_visualized.dart';
import 'sensorsdata_viewscreen_tabbar.dart';

///该类用于处理页面浏览一些公共的数据
@pragma("vm:entry-point")
class ViewScreenFactory {
  ///Route、Tab、BottomBar 负责更新

  ///通过 Route 路由跳转产生的页面浏览事件
  ViewScreenEvent? _lastRouteViewScreen;

  static final _instance = ViewScreenFactory._();

  ViewScreenFactory._();

  factory ViewScreenFactory.getInstance() => _instance;

  ViewScreenEvent? get lastRouteViewScreen => _lastRouteViewScreen;

  set lastRouteViewScreen(ViewScreenEvent? viewScreenEvent) {
    flushBeforeViewScreenObserver();
    this._lastRouteViewScreen = viewScreenEvent;
    flushAfterViewScreenObserver();
  }

  List<ViewScreenObserver> _viewScreenObservers = [];

  void addViewScreenObserver(ViewScreenObserver observer) {
    if (!_viewScreenObservers.contains(observer)) {
      _viewScreenObservers.add(observer);
    }
  }

  void flushBeforeViewScreenObserver() {
    _viewScreenObservers.forEach((element) {
      element.onBeforeViewScreen(lastViewScreen);
    });
  }

  void flushAfterViewScreenObserver() {
    _viewScreenObservers.forEach((element) {
      element.onAfterViewScreen(lastViewScreen);
    });
  }

  ///设置 bottom 页面浏览
  set bottomBarView(ViewScreenEvent? viewScreen) {
    tryCatchLambda(() {
      if (viewScreen != null && lastRouteViewScreen != null) {
        if (lastRouteViewScreen!.bottomBarViewScreen != null && lastRouteViewScreen!.tabBarViewScreen != null) {
          int bTime = lastRouteViewScreen!.bottomBarViewScreen!.updateTime;
          int tTime = lastRouteViewScreen!.tabBarViewScreen!.updateTime;
          //说明是 bottom 先添加到 route page view 中，tab 属于 bottom，bottom 改变，将其设置为 null。
          //否则说明是 tab 先添加到，bottom 后添加，正常更新 bottom
          if (bTime < tTime) {
            lastRouteViewScreen!.tabBarViewScreen = null;
          }
        }
        lastRouteViewScreen!.bottomBarViewScreen = viewScreen;
      }
    });
  }

  ///设置 tab 页面浏览
  set tabBarView(ViewScreenEvent? viewScreen) {
    tryCatchLambda(() {
      if (viewScreen != null && lastRouteViewScreen != null) {
        if (lastRouteViewScreen!.bottomBarViewScreen != null && lastRouteViewScreen!.tabBarViewScreen != null) {
          int bTime = lastRouteViewScreen!.bottomBarViewScreen!.updateTime;
          int tTime = lastRouteViewScreen!.tabBarViewScreen!.updateTime;
          //说明是 tab 先添加到 route page view 中，bottom 属于 tab，tab 改变，将其设置为 null。
          //否则说明是 bottom 先添加到，tab 后添加，正常更新 tab
          if (tTime < bTime) {
            lastRouteViewScreen!.bottomBarViewScreen = null;
          }
        }
        lastRouteViewScreen!.tabBarViewScreen = viewScreen..updateTime;
      }
    });
  }

  ///获取最终的页面浏览
  ViewScreenEvent? get lastViewScreen {
    if (lastRouteViewScreen != null) {
      if (lastRouteViewScreen!.bottomBarViewScreen != null && lastRouteViewScreen!.tabBarViewScreen != null) {
        int bTime = lastRouteViewScreen!.bottomBarViewScreen!.updateTime;
        int tTime = lastRouteViewScreen!.tabBarViewScreen!.updateTime;
        if (tTime > bTime) {
          return lastRouteViewScreen!.tabBarViewScreen;
        } else {
          return lastRouteViewScreen!.bottomBarViewScreen;
        }
      } else if (lastRouteViewScreen!.bottomBarViewScreen != null) {
        return lastRouteViewScreen!.bottomBarViewScreen;
      } else if (lastRouteViewScreen!.tabBarViewScreen != null) {
        return lastRouteViewScreen!.tabBarViewScreen;
      } else {
        return lastRouteViewScreen;
      }
    }
    return null;
  }

  ///根据 ViewScreenEvent 来判断
  ///特别是通过路由返回的时候，要触发对应页面中保存的 bottom 和 tab 的页面浏览
  void trackViewScreenForBack(ViewScreenEvent? viewScreenEvent) {
    tryCatchLambda(() {
      if (viewScreenEvent != null) {
        List<ViewScreenEvent> pageList = [];
        pageList.add(viewScreenEvent);

        if (viewScreenEvent.bottomBarViewScreen != null && viewScreenEvent.tabBarViewScreen != null) {
          int bTime = viewScreenEvent.bottomBarViewScreen!.updateTime;
          int tTime = viewScreenEvent.tabBarViewScreen!.updateTime;
          if (tTime > bTime) {
            pageList.add(viewScreenEvent.bottomBarViewScreen!);
            pageList.add(viewScreenEvent.tabBarViewScreen!);
          } else {
            pageList.add(viewScreenEvent.tabBarViewScreen!);
            pageList.add(viewScreenEvent.bottomBarViewScreen!);
          }
        } else if (viewScreenEvent.bottomBarViewScreen != null) {
          pageList.add(viewScreenEvent.bottomBarViewScreen!);
        } else if (viewScreenEvent.tabBarViewScreen != null) {
          pageList.add(viewScreenEvent.tabBarViewScreen!);
        }

        //触发最后的页面浏览事件
        if (pageList.isNotEmpty) {
          ViewScreenEvent? lastEvent = pageList.last;
          int? tabIndex;
          if (lastEvent == viewScreenEvent) {
            tabIndex = lastEvent.currentTabIndex;
          }
          Map map = lastEvent.toSDKMap()!;
          VisualizedStatusManager.getInstance().updatePageRefresh(false);
          trackViewScreenEvent(map[r"$screen_name"], map as Map<String, dynamic>?);
          TabViewScreenResolver.getInstance().resetIndex(currentIndex: tabIndex); //TODO 应该判断当前触发的是不是 tab 事件，如果是的话，就重新设定 index 索引
        }
      }
    });
  }

  ///触发页面浏览事件，在此会判断页面浏览功能是否可用。如果不可用就不触发页面浏览
  void trackViewScreenEvent(String url, Map<String, dynamic>? properties) async {
    bool isIgnored = await SensorsAnalyticsAutoTrackConfig.getInstance().isAutoTrackViewScreenIgnored();
    if (!isIgnored) {
      SensorsAnalyticsFlutterPlugin.trackViewScreen(url, properties);
    }
  }

  void printViewScreen(ViewScreenEvent event, [Map<String, Object?>? otherData]) {
    String result = "";
    result += "\n========================================ViewScreen=======================================\n";
    result += event.toString() + "\n";
    SAUtils.baseDeviceInfo.forEach((key, value) {
      result += "$key: $value\n";
    });
    otherData?.forEach((key, value) {
      result += "$key: $value\n";
    });
    result += "=========================================================================================";
    SaLogger.p(result);
  }
}

@pragma("vm:entry-point")
class ViewScreenEvent {
  String? routeName;
  String? widgetName;
  String? fileName;
  String? importUri;
  String? title;
  BuildContext? buildContext;

  ///if current BuildContext has NavigationBar or TabBar's ViewScreenEvent，
  ///we need save it, and resume this ViewScreenEvent after back to this Route page.
  ViewScreenEvent? bottomBarViewScreen;
  ViewScreenEvent? tabBarViewScreen;

  ///用于辅助计算 Bottom 和 Tab 的页面浏览
  int updateTime = DateTime.now().millisecondsSinceEpoch;

  ///用于辅助记录 Tab 所在的 index，只有 Tab Page 才应该设置该值
  int currentTabIndex = -1;

  ///ISensorsDataViewScreen 中属性
  String? viewScreenName;
  String? viewScreenTitle;
  String? viewScreenUrl;
  Map<String, dynamic>? trackProperties;

  ViewScreenEvent();

  @override
  String toString() {
    return 'ViewScreenEvent{routeName: $routeName, widgetName: $widgetName, fileName: $fileName, importUri: $importUri, title: $title}';
  }

  ///for debug
  Map<String, dynamic> toMap() {
    return {
      "flutter_screen_route_name": '$routeName',
      "flutter_screen_widget_name": '$widgetName',
      "flutter_screen_widget_file_name": '$fileName',
      "flutter_screen_title": '$title'
    };
  }

  Map<String, dynamic>? toSDKMap({bool isClick = false}) {
    String? result = fileName;
    if (importUri != null) {
      result = importUri;
    }

    Map<String, dynamic>? _sdkMap = {r'$lib_method': "autoTrack"};
    if (viewScreenName != null) {
      _sdkMap[r"$screen_name"] = '$viewScreenName';
    } else {
      _sdkMap[r"$screen_name"] = '$result/$widgetName';
    }

    if (viewScreenTitle != null) {
      _sdkMap[r"$title"] = '$viewScreenTitle';
    } else if (title != null) {
      _sdkMap[r"$title"] = '$title';
    }
    if (!isClick) {
      if (viewScreenUrl != null) {
        _sdkMap[r"$url"] = '$viewScreenUrl';
      } else {
        _sdkMap[r"$url"] = '$result/$widgetName';
      }
    }
    if (trackProperties != null) {
      _sdkMap.addEntries(trackProperties!.entries);
    }
    return _sdkMap;
  }

  String? get finalTitle => viewScreenTitle != null ? "$viewScreenTitle" : '$title';

  String? get finalScreenName {
    String? result = fileName;
    if (importUri != null) {
      result = importUri;
    }
    if (viewScreenName != null) {
      return '$viewScreenName';
    } else {
      return '$result/$widgetName';
    }
  }
}

///用于记录页面浏览的周期
abstract class ViewScreenObserver {
  /// [previousEvent] 触发页面浏览事件前的页面信息
  void onBeforeViewScreen(ViewScreenEvent? previousEvent) {}

  ///[newEvent] 触发页面浏览后的页面信息
  void onAfterViewScreen(ViewScreenEvent? newEvent) {}
}
