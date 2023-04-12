import 'package:sa_aspectd_impl/appclick/sensorsdata_appclick.dart';
import 'package:sa_aspectd_impl/common/sensorsdata_common.dart';
import 'package:sa_aspectd_impl/viewscreen/sensorsdata_viewscreen_bottombar.dart';
import 'aop/aop.dart';
import 'sa_autotrack.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'viewscreen/sensorsdata_viewscreen_route.dart';
import 'viewscreen/sensorsdata_viewscreen_tabbar.dart';
import 'visualized/sensorsdata_visualized.dart';

@Aspect()
@pragma("vm:entry-point")
class SensorsAnalyticsTabBarAOP {
  @pragma("vm:entry-point")
  SensorsAnalyticsTabBarAOP();

  ///当设置为 build 方法时，会导致 BottomNavigationBar 也会触发，应该是 AspectD 的 bug。
  @Execute("package:flutter/src/material/tabs.dart", "_TabBarState", "-build")
  @pragma("vm:entry-point")
  dynamic _trackTabViewScreen(PointCut pointCut) {
    dynamic target = pointCut.target;
    dynamic result = pointCut.proceed();
    tryCatchLambda(() {
      if (target.runtimeType.toString().startsWith("_TabBarState")) {
        dynamic tabBarWidget = target.widget;
        final TabController controller = tabBarWidget.controller ?? DefaultTabController.of(target.context)!;
        TabViewScreenResolver.getInstance().trackTabViewScreen(target.hashCode, tabBarWidget, target.context, controller.index);
      }
    });
    return result;
  }

  @Execute("package:flutter/src/material/tabs.dart", "_TabBarState", "-dispose")
  @pragma("vm:entry-point")
  dynamic _trackTabBarStateDispose(PointCut pointCut) {
    dynamic target = pointCut.target;
    dynamic result = pointCut.proceed();
    tryCatchLambda(() {
      if (target.runtimeType.toString().startsWith("_TabBarState")) {
        TabViewScreenResolver.getInstance().dispose(target.hashCode);
      }
    });
    return result;
  }

  @Execute("package:flutter/src/material/tabs.dart", "_TabBarState", "-_handleTabControllerTick")
  @pragma("vm:entry-point")
  dynamic _trackTabBarStateNotify(PointCut pointCut) {
    dynamic target = pointCut.target;
    dynamic result = pointCut.proceed();
    tryCatchLambda(() {
      if (target.runtimeType.toString().startsWith("_TabBarState")) {
        dynamic tabBarWidget = target.widget;
        final TabController controller = tabBarWidget.controller ?? DefaultTabController.of(target.context)!;
        TabViewScreenResolver.getInstance().handleTabControllerTick(target.hashCode, controller.index);
      }
    });
    return result;
  }
}
