import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:sa_aspectd_impl/common/sensorsdata_logger.dart';
import 'package:sa_aspectd_impl/config/sensorsdata_autotrack_config.dart';
import 'package:sensors_analytics_flutter_plugin/sensors_analytics_flutter_plugin.dart';

import '../common/sensorsdata_common.dart';
import '../common/sensorsdata_page_info.dart';
import '../sa_autotrack.dart' show hasCreationLocation, getLocationInfo;
import '../visualized/sensorsdata_visualized.dart';
import '../visualized/sensorsdata_visualized_channel.dart';
import 'sensorsdata_viewscreen.dart';
import 'sensorsdata_viewscreen_route.dart';

@pragma("vm:entry-point")
class TabViewScreenResolver {
  ///上一个 Tab 对应的 index，如果 index 相同，则不应该触发页面浏览
  ///如果 _tabBar 不同，那么 _lastTabIndex 也需要设置为默认值
  int _lastTabIndex = -1;
  bool _isHandling = false;

  ///通常用于搜索相对应的 Tab Widget
  bool _isFoundTargetTab = false;
  Timer? _timer;

  ///最后一个 GestureDetector，在寻找目标 Tab Item 的时候记录一下，后面会用于计算 Content
  Element? _lastGestureDetectorElement;
  String? _elementContent;

  static final _instance = TabViewScreenResolver._();

  TabViewScreenResolver._();

  factory TabViewScreenResolver.getInstance() => _instance;

  void persistentFrameCallback(Duration timeStamp) {
    //SaLogger.p("persistent frame callback====");
  }

  void trackTabViewScreen(Widget? tabBarWidget, BuildContext? context, int index) {
    try {
      if (!SensorsAnalyticsAutoTrackConfig.getInstance().isTabBarPageViewEnabled) {
        return;
      }
      if (_timer != null && _timer!.isActive) {
        _timer!.cancel();
        _isHandling = false;
      } else if (_isHandling) {
        return;
      }

      _timer = Timer(Duration(milliseconds: 100), () {
        _isHandling = true;
        if (index != _lastTabIndex) {
          TabBar tabBar = tabBarWidget! as TabBar;
          Widget tabItemWidget = tabBar.tabs[index];
          _findTargetTabWidget(context! as Element, tabItemWidget);
          if (_isFoundTargetTab) {
            ViewScreenEvent screenEvent = ViewScreenEvent();
            if (hasCreationLocation(tabItemWidget)) {
              Map<String, dynamic> locationMap = getLocationInfo(tabItemWidget);
              if (locationMap["file"] != null) {
                screenEvent.fileName = locationMap["file"]!.replaceAll(locationMap["rootUrl"]!, "");
              }
              screenEvent.importUri = locationMap["importUri"];
            }
            if (_elementContent != null) {
              screenEvent.title = "$_elementContent";
            }
            screenEvent.widgetName = tabItemWidget.runtimeType.toString();
            screenEvent.routeName = ViewScreenFactory.getInstance().lastViewScreen?.routeName;

            Map<String, dynamic>? map = screenEvent.toSDKMap()!;
            SAUtils.setupLibPluginVersion(map);

            //如果引用值为空，表示第一次使用，对于第一次使用，做一个延迟处理，保障 bottom_navigation_bar 先触发
            if (_lastTabIndex == -1) {
              Future.delayed(Duration(milliseconds: 500), () {
                screenEvent.updateTime = DateTime.now().millisecondsSinceEpoch;
                SensorsAnalyticsFlutterPlugin.trackViewScreen(map[r"$screen_name"], map);
                _lastTabIndex = index;
                screenEvent.currentTabIndex = _lastTabIndex;
                ViewScreenFactory.getInstance().tabBarView = screenEvent;
                VisualizedStatusManager.getInstance().updatePageRefresh(false, forceUpdate: SensorsAnalyticsVisualized.isVisualizedConnected);
                _resetViewScreen();
              });
            } else {
              screenEvent.updateTime = DateTime.now().millisecondsSinceEpoch;
              SensorsAnalyticsFlutterPlugin.trackViewScreen(map[r"$screen_name"], map);
              _lastTabIndex = index;
              screenEvent.currentTabIndex = _lastTabIndex;
              ViewScreenFactory.getInstance().tabBarView = screenEvent;
              VisualizedStatusManager.getInstance().updatePageRefresh(false, forceUpdate: SensorsAnalyticsVisualized.isVisualizedConnected);
              _resetViewScreen();
            }
          } else {
            _resetViewScreen();
          }
        } else {
          _resetViewScreen();
        }
      });
    } catch (e, s) {
      SaLogger.e("SensorsAnalytics Exception Report", stackTrace: s, error: e);
    }
  }

  void _findTargetTabWidget(Element element, Widget tabItemWidget) {
    if (_isFoundTargetTab) {
      return;
    }
    if (element.widget is GestureDetector) {//TODO instead of [SAUtils.isGestureDetector] ?
      _lastGestureDetectorElement = element;
    }
    if (element.widget == tabItemWidget) {
      if (_lastGestureDetectorElement != null) {
        _elementContent = SAUtils.resolvingWidgetContent(_lastGestureDetectorElement!, searchGestureDetector: false);
      }
      _isFoundTargetTab = true;
      return;
    }
    element.visitChildElements((element) {
      _findTargetTabWidget(element, tabItemWidget);
    });
  }

  void _resetViewScreen() {
    _isFoundTargetTab = false;
    _timer = null;
    _lastGestureDetectorElement = null;
    _elementContent = null;
    _isHandling = false;
  }

  ///当页面浏览发生变化时，例如路由跳转、或者 bottom navigation bar 点击等，需要重置 tab index
  void resetIndex({int? currentIndex}) {
    _lastTabIndex = currentIndex ?? -1;
  }
}
