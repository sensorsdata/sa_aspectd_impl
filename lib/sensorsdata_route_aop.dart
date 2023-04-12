import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'aop/aop.dart';
import 'sa_autotrack.dart';
import 'viewscreen/sensorsdata_viewscreen_route.dart';

//主要是处理与路由相关的 AOP 操作
@Aspect()
@pragma("vm:entry-point")
class SensorsAnalyticsRouteAOP {
  @pragma("vm:entry-point")
  SensorsAnalyticsRouteAOP();

  ///处理 route 的回调
  @Execute("package:flutter/src/widgets/navigator.dart", "_RouteEntry", "-handleAdd")
  @pragma("vm:entry-point")
  void _routeHandleAdd(PointCut pointCut) {
    dynamic target = pointCut.target;
    dynamic preRoute = pointCut.namedParams["previousPresent"];
    pointCut.proceed();
    RouteViewScreenResolver.getInstance().didPush(target.route, preRoute);
  }

  ///处理 route 的回调
  @Execute("package:flutter/src/widgets/navigator.dart", "_RouteEntry", "-handlePush")
  @pragma("vm:entry-point")
  void _routeHandlePush(PointCut pointCut) {
    dynamic target = pointCut.target;
    dynamic previousPresent = pointCut.namedParams["previousPresent"];
    dynamic previousState = target.currentState;
    pointCut.proceed();
    //previousState == _RouteLifecycle.replace || previousState == _RouteLifecycle.pushReplace
    if (previousState.index == 6 || previousState.index == 4) {
      RouteViewScreenResolver.getInstance().didReplace(target.route, previousPresent);
    } else {
      RouteViewScreenResolver.getInstance().didPush(target.route, previousPresent);
    }
    print("=----=============_routeHandlePush");
  }

  ///处理 route 的回调
  @Execute("package:flutter/src/widgets/navigator.dart", "_RouteEntry", "-handlePop")
  @pragma("vm:entry-point")
  dynamic _handlePop(PointCut pointCut) {
    dynamic target = pointCut.target;
    dynamic previousPresent = pointCut.namedParams["previousPresent"];
    dynamic result = pointCut.proceed();
    RouteViewScreenResolver.getInstance().didPop(target.route, previousPresent);
    return result;
  }

  ///处理 route 的回调
  @Execute("package:flutter/src/widgets/navigator.dart", "_RouteEntry", "-handleRemoval")
  @pragma("vm:entry-point")
  void _handleRemoval(PointCut pointCut) {
    dynamic target = pointCut.target;
    dynamic previousPresent = pointCut.namedParams["previousPresent"];
    pointCut.proceed();
    RouteViewScreenResolver.getInstance().didRemove(target.route, previousPresent);
  }

  @Execute("package:flutter/src/widgets/navigator.dart", "_RouteEntry", "-dispose")
  @pragma("vm:entry-point")
  void _handleRouteDispose(PointCut pointCut) {
    dynamic target = pointCut.target;
    pointCut.proceed();
    //下面这么判断的原因是 AspectD 似乎插桩有问题，会在 _AnyTapGestureRecognizer 中插桩，所以这版做一个判断
    if (target.runtimeType.toString() == "_RouteEntry") {
      RouteViewScreenResolver.getInstance().routeDispose(target.route);
    }
  }

  ///适配 PageRouteBuilder
  ///目前发现当 hook PageRouteBuilder 的时候，具体使用 material、cupertio 对应的 route，
  ///与谁先 hook 有关系，应该是 AspectD 的一个 bug
  ///TODO 此作为已知问题进行推进
  @Execute("package:flutter/src/widgets/pages.dart", "PageRouteBuilder", "-buildPage")
  @pragma("vm:entry-point")
  dynamic _trackPageRouteViewScreen(PointCut pointCut) {
    Route target = pointCut.target as Route<dynamic>;
    dynamic widgetResult = pointCut.proceed();
    RouteViewScreenResolver.getInstance().buildPage(target, widgetResult, pointCut.positionalParams[0]);
    return widgetResult;
  }

  @Execute("package:flutter/src/material/page.dart", "MaterialRouteTransitionMixin", "-buildPage")
  @pragma("vm:entry-point")
  dynamic _trackViewScreen(PointCut pointCut) {
    Route target = pointCut.target as Route<dynamic>;
    dynamic widgetResult = pointCut.proceed();
    RouteViewScreenResolver.getInstance().buildPage(target, widgetResult, pointCut.positionalParams[0]);
    return widgetResult;
  }

  ///适配 cupertino widget
  @Execute("package:flutter/src/cupertino/route.dart", "CupertinoRouteTransitionMixin", "-buildPage")
  @pragma("vm:entry-point")
  dynamic _trackCupertinoViewScreen(PointCut pointCut) {
    Route target = pointCut.target as Route<dynamic>;
    dynamic widgetResult = pointCut.proceed();
    RouteViewScreenResolver.getInstance().buildPage(target, widgetResult, pointCut.positionalParams[0]);
    return widgetResult;
  }

  ///初始化一个 frame callback，用于获取刷新的时机
  @Execute('package:flutter/src/rendering/binding.dart', 'RendererBinding', '-initInstances')
  @pragma('vm:entry-point')
  void _hookRendererBinding(PointCut pointcut) {
    dynamic target = pointcut.target;
    pointcut.proceed();
    target.addPersistentFrameCallback(SensorsDataAPI.getInstance().persistentFrameCallback);
  }

  @Execute("package:get/get_navigation/src/routes/default_route.dart", "GetPageRoute", "-buildPage")
  @pragma("vm:entry-point")
  dynamic _trackGetPluginPageRoute(PointCut pointCut) {
    dynamic target = pointCut.target;
    dynamic context = pointCut.positionalParams[0];
    dynamic widgetResult = pointCut.proceed();
    if (target.runtimeType.toString().contains("GetPageRoute")) {
      return widgetResult;
    }
    dynamic realWidget = target.builder(context);
    RouteViewScreenResolver.getInstance().buildPage(target, realWidget, pointCut.positionalParams[0]);
    return widgetResult;
  }

  @Execute("package:get/get_navigation/src/routes/get_transition_mixin.dart", "GetPageRouteTransitionMixin", "-buildPage")
  @pragma("vm:entry-point")
  dynamic _trackGetPluginPageRoute2(PointCut pointCut) {
    dynamic target = pointCut.target;
    dynamic context = pointCut.positionalParams[0];
    dynamic widgetResult = pointCut.proceed();
    dynamic realWidget = target.builder(context);
    RouteViewScreenResolver.getInstance().buildPage(target, realWidget, pointCut.positionalParams[0]);
    return widgetResult;
  }
}
