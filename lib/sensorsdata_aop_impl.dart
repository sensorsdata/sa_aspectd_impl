import 'package:sa_aspectd_impl/appclick/sensorsdata_appclick.dart';
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
class SensorsAnalyticsAOP {
  @pragma("vm:entry-point")
  SensorsAnalyticsAOP();

  @Execute("package:flutter/src/widgets/framework.dart", "Element", "-mount")
  @pragma('vm:entry-point')
  void _hookElementMount(PointCut pointCut) {
    List<dynamic> params = pointCut.positionalParams;
    Element? parentElement = params[0];
    VisualizedStatusManager.getInstance().mount(parentElement);
    pointCut.proceed();
  }

  @Execute("package:flutter/src/widgets/framework.dart", "Element", "-unmount")
  @pragma('vm:entry-point')
  void _hookElementUnmount(PointCut pointCut) {
    pointCut.proceed();
    VisualizedStatusManager.getInstance().unmount();
  }

  //配合 sa_autotrack.dart 相关逻辑，用于替换 persistent frame callback
  @Execute("package:flutter/src/scheduler/binding.dart", "SchedulerBinding", "-handleDrawFrame")
  @pragma("vm:entry-point")
  void _handleDrawFrame(PointCut pointCut) {
    SensorsDataAPI.getInstance().updateRoute();
    RouteViewScreenResolver.getInstance().beforeHandleDrawFrame();
    pointCut.proceed();
    VisualizedStatusManager.getInstance().handleDrawFrame();
    RouteViewScreenResolver.getInstance().afterHandleDrawFrame();
  }

  //配合计算 ExpansionPanelList 中 Header 对应的点击事件
  @Execute("package:flutter/src/material/expansion_panel.dart", "_ExpansionPanelListState", "-_handlePressed")
  @pragma("vm:entry-point")
  void _handleExpansionPanelPressed(PointCut pointCut) {
    List<dynamic> params = pointCut.positionalParams;
    int index = params[1];
    AppClickResolver.getInstance().handleExpansionPanelPressed(index);
    pointCut.proceed();
  }

  ///BottomNavigationBar 页面浏览事件
  @Execute("package:flutter/src/material/bottom_navigation_bar.dart", "_BottomNavigationBarState", "-_rebuild")
  @pragma("vm:entry-point")
  void _trackBottomNavigationViewScreen(PointCut pointCut) {
    dynamic target = pointCut.target;
    pointCut.proceed();
    BottomBarViewScreenResolver.getInstance().trackBottomNavigationBarViewScreen(target.widget, target.context);
  }

  @Execute("package:flutter/src/gestures/binding.dart", "GestureBinding", "-dispatchEvent")
  @pragma("vm:entry-point")
  dynamic _trackHitTest(PointCut pointCut) {
    dynamic hitTestResult = pointCut.positionalParams[1];
    dynamic pointEvent = pointCut.positionalParams[0];
    if (pointEvent is PointerUpEvent) {
      //flutter 2.2.0 后 TextSpan 实现了 HitTestTarget 接口，如果直接转换成 RenderObject 会有问题
      for (final HitTestEntry entry in hitTestResult.path) {
        if (entry.target is RenderObject) {
          AppClickResolver.getInstance().trackHitTest(entry, pointEvent);
          break;
        }
      }
    }
    return pointCut.proceed();
  }

  @Execute("package:flutter/src/gestures/recognizer.dart", "GestureRecognizer", "-invokeCallback")
  @pragma("vm:entry-point")
  dynamic _trackClick(PointCut pointCut) {
    dynamic result = pointCut.proceed();
    dynamic eventName = pointCut.positionalParams[0];
    AppClickResolver.getInstance().trackClick(eventName);
    return result;
  }

  @Execute("package:flutter/src/widgets/framework.dart", "RenderObjectElement", "-mount")
  @pragma('vm:entry-point')
  void _hookRenderObjectElementMount(PointCut pointCut) {
    Element element = pointCut.target as Element;
    pointCut.proceed();
    if (kReleaseMode || kProfileMode) {
      element.renderObject!.debugCreator = DebugCreator(element);
    }
  }

  @Execute('package:flutter/src/widgets/framework.dart', 'RenderObjectElement', '-update')
  @pragma('vm:entry-point')
  void _hookRenderObjectElementUpdate(PointCut pointCut) {
    Element element = pointCut.target as Element;
    pointCut.proceed();
    if (kReleaseMode || kProfileMode) {
      element.renderObject!.debugCreator = DebugCreator(element);
    }
  }

  ///初始化一个 frame callback，用于获取刷新的时机
  @Execute('package:flutter/src/rendering/binding.dart', 'RendererBinding', '-initInstances')
  @pragma('vm:entry-point')
  void _hookRendererBinding(PointCut pointcut) {
    dynamic target = pointcut.target;
    pointcut.proceed();
    target.addPersistentFrameCallback(SensorsDataAPI.getInstance().persistentFrameCallback);
  }

  void _printHookDebugInfo(dynamic target, dynamic result, PointCut pointCut) {
    print("====_printHookInfo=============");
    print("====target===${target}");
    print("=====result===${result}");
    print("====named params====${pointCut.namedParams}");
    print("====position params====${pointCut.positionalParams}");
    //print('=====source info====${pointCut.sourceInfos.toString()}');
    pointCut.positionalParams.forEach((element) {
      print("====${element.runtimeType}");
    });
  }
}
