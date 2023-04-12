import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sa_aspectd_impl/common/sensorsdata_logger.dart';
import 'package:sa_aspectd_impl/config/sensorsdata_autotrack_config.dart';

import '../common/sensorsdata_common.dart';
import '../sa_autotrack.dart' show hasCreationLocation, getLocationInfo;
import '../visualized/sensorsdata_visualized.dart';
import '../visualized/sensorsdata_visualized_channel.dart';
import 'sensorsdata_viewscreen.dart';

@pragma("vm:entry-point")
class TabViewScreenResolver {
  ///key 是 _TabBarState 对应的 hasCode, value _TabStatusEntity 是当前 Tab 对应的状态信息
  Map<int, _TabStatusEntity> _tabStateWithIndexMap = {};

  ///上一个 Tab 对应的 index，如果 index 相同，则不应该触发页面浏览
  ///如果 _tabBar 不同，那么 _lastTabIndex 也需要设置为默认值
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

  void handleTabControllerTick(int tabBarStateHasCode, int index) {
    var state = _tabStateWithIndexMap[tabBarStateHasCode];
    if (state == null || state.isIndexChanged) {
      return;
    }
    if (state.currentIndex != index) {
      state.isIndexChanged = true;
    }
  }

  void trackTabViewScreen(int tabBarStateHasCode, Widget? tabBarWidget, BuildContext? context, int index) {
    try {
      if (!SensorsAnalyticsAutoTrackConfig.getInstance().isBottomAndTabBarPageViewEnabled) {
        return;
      }
      var state = _tabStateWithIndexMap[tabBarStateHasCode];
      if (state != null && !state.isIndexChanged) {
        return;
      } else if (state == null) {
        state = _TabStatusEntity();
        state.isIndexChanged = true;
        state.tabBarStateHasCode = tabBarStateHasCode;
        _tabStateWithIndexMap[tabBarStateHasCode] = state;
      }
      if (_timer != null && _timer!.isActive) {
        _timer!.cancel();
        _isHandling = false;
      } else if (_isHandling) {
        return;
      }
      _timer = Timer(Duration(milliseconds: 100), () {
        _isHandling = true;

        if (state!.isIndexChanged) {
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
            if (state.currentIndex == -1) {
              Future.delayed(Duration(milliseconds: 500), () {
                screenEvent.updateTime = DateTime.now().millisecondsSinceEpoch;
                ViewScreenFactory.getInstance().flushBeforeViewScreenObserver();
                ViewScreenFactory.getInstance().trackViewScreenEvent(map[r"$screen_name"], map);
                state!.currentIndex = index;
                state.isIndexChanged = false;
                screenEvent.currentTabIndex = state.currentIndex!;
                ViewScreenFactory.getInstance().tabBarView = screenEvent;
                ViewScreenFactory.getInstance().flushAfterViewScreenObserver();
                VisualizedStatusManager.getInstance().updatePageRefresh(false, forceUpdate: SensorsAnalyticsVisualized.isVisualizedConnected);
                _resetViewScreen();
              });
            } else {
              screenEvent.updateTime = DateTime.now().millisecondsSinceEpoch;
              ViewScreenFactory.getInstance().flushBeforeViewScreenObserver();
              ViewScreenFactory.getInstance().trackViewScreenEvent(map[r"$screen_name"], map);
              state.currentIndex = index;
              state.isIndexChanged = false;
              screenEvent.currentTabIndex = state.currentIndex!;
              ViewScreenFactory.getInstance().tabBarView = screenEvent;
              ViewScreenFactory.getInstance().flushAfterViewScreenObserver();
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

  ///删除对应的值
  void dispose(int targetHasCode) {
    _tabStateWithIndexMap.remove(targetHasCode);
  }

  void _findTargetTabWidget(Element element, Widget tabItemWidget) {
    if (_isFoundTargetTab) {
      return;
    }
    if (element.widget is GestureDetector) {
      //TODO instead of [SAUtils.isGestureDetector] ?
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
    //_lastTabIndex = currentIndex ?? -1;
  }
}

///记录 Tab 的状态
class _TabStatusEntity {
  ///哈希值
  int? tabBarStateHasCode;

  ///当前选中的值
  int currentIndex = -1;

  ///前一个
  int previousIndex = -1;

  ///标志状态是否发生变化，当 currentIndex 值变动的时候，需要更改
  bool isIndexChanged = false;
}
