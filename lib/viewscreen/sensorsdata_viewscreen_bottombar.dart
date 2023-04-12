import 'dart:async';

import 'package:flutter/material.dart';

import '../common/sensorsdata_common.dart';
import '../common/sensorsdata_logger.dart';
import '../config/sensorsdata_autotrack_config.dart';
import '../sa_autotrack.dart' show hasCreationLocation, getLocationInfo;
import '../visualized/sensorsdata_visualized.dart';
import '../visualized/sensorsdata_visualized_channel.dart';
import 'sensorsdata_viewscreen.dart';
import 'sensorsdata_viewscreen_tabbar.dart';

@pragma("vm:entry-point")
class BottomBarViewScreenResolver {
  List<String> bottomBarContentList = [];

  List<String> contentList = [];

  ///BottomNavigationBar 使用
  Timer? _timer;

  //存放页面浏览时的相关信息
  var appBarTitle;
  var appTitleWidget;

  static final _instance = BottomBarViewScreenResolver._();

  BottomBarViewScreenResolver._();

  factory BottomBarViewScreenResolver.getInstance() => _instance;

  void trackBottomNavigationBarViewScreen(BottomNavigationBar? navigationBar, BuildContext context) {
    try {
      if (!SensorsAnalyticsAutoTrackConfig.getInstance().isBottomAndTabBarPageViewEnabled) {
        return;
      }
      if (_timer != null && _timer!.isActive) {
        _timer!.cancel();
      }
      _timer = Timer(Duration(milliseconds: 100), () {
        ViewScreenEvent viewScreenEvent = ViewScreenEvent();
        Widget? _viewScreenWidget = navigationBar;

        if (hasCreationLocation(_viewScreenWidget)) {
          Map<String, dynamic> locationMap = getLocationInfo(_viewScreenWidget!);

          if (locationMap["file"] != null) {
            viewScreenEvent.fileName = locationMap["file"]!.replaceAll(locationMap["rootUrl"]!, "");
          }
          viewScreenEvent.importUri = locationMap["importUri"];
        }

        String? clickContent;
        bottomBarContentList.clear();
        clickContent = navigationBar!.items[navigationBar.currentIndex].label;
        if (clickContent == null) {
          appBarTitle = null;
          dynamic barItem = navigationBar.items[navigationBar.currentIndex];
          try {
            //适配 flutter 2.10.0 BottomNavigationBarItem API 的变化
            appBarTitle = barItem.label;
            if (appBarTitle == null) {
              appBarTitle = barItem.tooltip;
            }
            clickContent = appBarTitle;
          } catch (e) {
            //flutter 2.10.0 之前的做法
            appTitleWidget = barItem.title;
            _getBottomNavigationBarWidget(context as Element);
          }
        }
        if (clickContent == null) {
          clickContent = navigationBar.items[navigationBar.currentIndex].tooltip;
        }
        viewScreenEvent.title = clickContent;
        viewScreenEvent.widgetName = "BottomNavigationBar";
        viewScreenEvent.routeName = ViewScreenFactory.getInstance().lastViewScreen?.routeName;
        viewScreenEvent.updateTime = DateTime.now().millisecondsSinceEpoch;
        Map map = viewScreenEvent.toSDKMap()!;
        ViewScreenFactory.getInstance().flushBeforeViewScreenObserver();
        ViewScreenFactory.getInstance().trackViewScreenEvent(map[r"$screen_name"], map as Map<String, dynamic>?);
        TabViewScreenResolver.getInstance().resetIndex();
        ViewScreenFactory.getInstance().bottomBarView = viewScreenEvent;
        ViewScreenFactory.getInstance().flushAfterViewScreenObserver();
        VisualizedStatusManager.getInstance().updatePageRefresh(false, forceUpdate: SensorsAnalyticsVisualized.isVisualizedConnected);
      });
    } catch (e, s) {
      SaLogger.e("SensorsAnalytics Exception Report", stackTrace: s, error: e);
    }
  }

  void _getBottomAppBar(Element element) {
    if (element.widget is AppBar) {
      appTitleWidget = (element.widget as AppBar).title;
    }
    if (element.widget == appTitleWidget) {
      _getBottomAppBarElementContentByType(element);
      if (bottomBarContentList.isNotEmpty) {
        String result = bottomBarContentList.join("-");
        appBarTitle = result;
      }
    } else {
      element.visitChildElements(_getBottomAppBar);
    }
  }

  void _getBottomNavigationBarWidget(Element element) {
    if (element.widget == appTitleWidget) {
      _getBottomAppBarElementContentByType(element);
      if (bottomBarContentList.isNotEmpty) {
        String result = bottomBarContentList.join("-");
        appBarTitle = result;
      }
    } else {
      element.visitChildElements(_getBottomAppBar);
    }
  }

  void _getBottomAppBarElementContentByType(Element? element) {
    if (element != null) {
      String? tmp = SAUtils.try2GetText(element.widget);
      if (tmp != null) {
        bottomBarContentList.add(tmp);
        return;
      }
      element.visitChildElements(_getBottomAppBarElementContentByType);
    }
  }
}
