import 'package:flutter/widgets.dart';
import 'package:sa_aspectd_impl/common/sensorsdata_common.dart';
import 'package:sa_aspectd_impl/common/sensorsdata_logger.dart';
import 'package:sensors_analytics_flutter_plugin/sensors_analytics_flutter_plugin.dart';

import '../config/sensorsdata_autotrack_config.dart';
import '../viewscreen/sensorsdata_viewscreen.dart';

class PageLeaveResolver extends ViewScreenObserver with WidgetsBindingObserver {
  DateTime? _pageStartTime;

  //来源页面、向前页面
  String? referrer;

  bool isPausedTrigger = false;

  @override
  void onBeforeViewScreen(ViewScreenEvent? previousEvent) {
    ///需要计算上一个页面的页面停留时长
    if (SensorsAnalyticsAutoTrackConfig.getInstance().isPageLeaveEnabled) {
      if (_pageStartTime != null && previousEvent != null) {
        _trackPageLeave(previousEvent, DateTime.now().millisecondsSinceEpoch - _pageStartTime!.millisecondsSinceEpoch);
      }
      _pageStartTime = null;
    }
  }

  @override
  void onAfterViewScreen(ViewScreenEvent? newEvent) {
    ///开始下一个页面的页面时长计算
    if (SensorsAnalyticsAutoTrackConfig.getInstance().isPageLeaveEnabled) {
      _pageStartTime = DateTime.now();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    //计算当前页面的页面停留时长
    if (state == AppLifecycleState.paused) {
      isPausedTrigger = true;
      if (SensorsAnalyticsAutoTrackConfig.getInstance().isPageLeaveEnabled) {
        onBeforeViewScreen(ViewScreenFactory.getInstance().lastViewScreen);
      }
    }
    //触发页面浏览
    else if (state == AppLifecycleState.resumed && isPausedTrigger) {
      isPausedTrigger = false;
      if (SensorsAnalyticsAutoTrackConfig.getInstance().isPageLeaveEnabled) {
        onAfterViewScreen(ViewScreenFactory.getInstance().lastViewScreen);
      }
      if (SensorsAnalyticsAutoTrackConfig.getInstance().isEnableForegroundAndBackgroundViewScreen) {
        ViewScreenFactory.getInstance().trackViewScreenForBack(ViewScreenFactory.getInstance().lastViewScreen);
      }
    }
  }

  void _trackPageLeave(ViewScreenEvent? previousEvent, int millisecondsDuration) async {
    tryCatchLambda(() async {
      if (previousEvent == null) {
        return;
      }
      Map<String, dynamic>? properties = previousEvent.toSDKMap();
      if (properties == null) {
        SaLogger.w("track page leave's page info is null, so return.");
        return;
      }
      double duration = millisecondsDuration / 1000.0;
      if (duration < 0.05) {
        return;
      }
      properties["event_duration"] = duration;

      ///如果全埋点不采集页面浏览，Flutter 将使用内部维护的页面浏览来源页面
      bool isIgnored = await SensorsAnalyticsAutoTrackConfig.getInstance().isAutoTrackViewScreenIgnored();
      if (isIgnored && referrer != null) {
        properties[r"$referrer"] = referrer;
      }
      SensorsAnalyticsFlutterPlugin.track(r"$AppPageLeave", properties);
      referrer = properties[r"$url"];
    });
  }
}
