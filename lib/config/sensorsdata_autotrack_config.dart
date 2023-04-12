import 'package:flutter/widgets.dart';
import 'package:sensors_analytics_flutter_plugin/sensors_analytics_flutter_plugin.dart';

import '../pageleave/sensorsdata_pageleave.dart';
import '../viewscreen/sensorsdata_viewscreen.dart';

///提供一些用于配置全埋点逻辑的方式
class SensorsAnalyticsAutoTrackConfig {
  static final _instance = SensorsAnalyticsAutoTrackConfig._();

  SensorsAnalyticsAutoTrackConfig._();

  factory SensorsAnalyticsAutoTrackConfig.getInstance() => _instance;

  ///用于配置全埋点是否自动处理 TabBar 对应的 PageView.
  ///若采集存在不准确的地方，请设置为 false，并由开发者自行处理 TabBar 对应的页面浏览
  bool isBottomAndTabBarPageViewEnabled = true;

  PageLeaveResolver? _widgetBindingObserver;

  ///判断是否开启页面停留功能
  bool get isPageLeaveEnabled => _isPageLeaveEnabled;
  bool _isPageLeaveEnabled = false;

  ///判断是否开启从后台进入前台触发页面浏览功能
  bool get isEnableForegroundAndBackgroundViewScreen => _isEnableForegroundAndBackgroundViewScreen;
  bool _isEnableForegroundAndBackgroundViewScreen = false;

  ///开始页面停留功能。页面停留自动支持前后台切换产生的页面浏览
  ///详见[enableForegroundAndBackgroundViewScreen]
  void enablePageLeave() {
    _isPageLeaveEnabled = true;
    _initPageObserver();
  }

  ///支持切后台切换产生的页面浏览。特别地，当从后台切换到前台后，会产生页面浏览事件。
  ///页面浏览事件是最后一次触发的页面浏览
  void enableForegroundAndBackgroundViewScreen(){
    _isEnableForegroundAndBackgroundViewScreen = true;
    _initPageObserver();
  }

  void _initPageObserver() {
    if (_widgetBindingObserver == null) {
      _widgetBindingObserver = PageLeaveResolver();
      ViewScreenFactory.getInstance().addViewScreenObserver(_widgetBindingObserver!);
      WidgetsBinding.instance.addObserver(_widgetBindingObserver!);
    }
  }

  Future<bool> isAutoTrackClickIgnored() async {
    return await SensorsAnalyticsFlutterPlugin.isAutoTrackEventTypeIgnored(SAAutoTrackType.APP_CLICK);
  }

  Future<bool> isAutoTrackViewScreenIgnored() async {
    return await SensorsAnalyticsFlutterPlugin.isAutoTrackEventTypeIgnored(SAAutoTrackType.APP_VIEW_SCREEN);
  }
}
