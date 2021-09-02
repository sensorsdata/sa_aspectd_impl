import 'package:aspectd/aspectd.dart';
import 'package:aspectd_impl/sa_autotrack.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

@Aspect()
@pragma("vm:entry-point")
class SensorsAnalyticsAOP {
  @pragma("vm:entry-point")
  SensorsAnalyticsAOP();


  // @Call("package:flutter/src/widgets/routes.dart", "ModalRoute",
  //     "-buildPage")
  // @pragma("vm:entry-point")
  // dynamic _routeBuildPage(PointCut pointCut) {
  //   print("==== route buildpage called ====");
  //   dynamic target = pointCut.target;
  //   print("==== ${target.runtimeType.toString()}");
  //
  //   print("==== ${pointCut.positionalParams}");
  //
  //   pointCut.positionalParams?.forEach((element) {
  //     print("位置参数：${element}");
  //     if(element is BuildContext){
  //       print("1111111111");
  //     }
  //   });
  //
  //   pointCut.namedParams?.forEach((key, value) {
  //     print("命名参数：$key=========$value");
  //   });
  //
  //   dynamic widgetResult = pointCut.proceed();
  //   SensorsDataAPI.getInstance().trackViewScreen(
  //       target, widgetResult, pointCut.positionalParams[0]);
  //
  //   return widgetResult;
  // }


  //配合 sa_autotrack.dart 相关逻辑，用于替换 persistent frame callback
  @Execute("package:flutter/src/scheduler/binding.dart", "SchedulerBinding",
      "-handleDrawFrame")
  @pragma("vm:entry-point")
  void _handleDrawFrame(PointCut pointCut) {
    SensorsDataAPI.getInstance().updateRoute();
    pointCut.proceed();
  }

  ///处理 route 的回调
  @Execute(
      "package:flutter/src/widgets/navigator.dart", "_RouteEntry", "-handleAdd")
  @pragma("vm:entry-point")
  void _routeHandleAdd(PointCut pointCut) {
    print("==route-handleAdd");
    dynamic target = pointCut.target;
    dynamic preRoute = pointCut.namedParams["previousPresent"];
    pointCut.proceed();
    SensorsDataAPI.getInstance().didPush(target.route, preRoute);
  }

  ///处理 route 的回调
  @Execute(
      "package:flutter/src/widgets/navigator.dart", "_RouteEntry", "-handlePush")
  @pragma("vm:entry-point")
  void _routeHandlePush(PointCut pointCut) {
    print("==route-handleAdd");
    dynamic target = pointCut.target;
    dynamic previousPresent = pointCut.namedParams["previousPresent"];
    dynamic previousState = target.currentState;
    pointCut.proceed();
    //previousState == _RouteLifecycle.replace || previousState == _RouteLifecycle.pushReplace
    if (previousState.index == 6 || previousState.index == 4) {
      SensorsDataAPI.getInstance().didReplace(target.route, previousPresent);
    } else {
      SensorsDataAPI.getInstance().didPush(target.route, previousPresent);
    }
  }

  ///处理 route 的回调
  @Execute(
      "package:flutter/src/widgets/navigator.dart", "_RouteEntry", "-handlePop")
  @pragma("vm:entry-point")
  void _handlePop(PointCut pointCut) {
    dynamic target = pointCut.target;
    dynamic previousPresent = pointCut.namedParams["previousPresent"];
    pointCut.proceed();
    SensorsDataAPI.getInstance().didPop(target.route, previousPresent);
  }

  ///处理 route 的回调
  @Execute(
      "package:flutter/src/widgets/navigator.dart", "_RouteEntry", "-handleRemoval")
  @pragma("vm:entry-point")
  void _handleRemoval(PointCut pointCut) {
    dynamic target = pointCut.target;
    dynamic previousPresent = pointCut.namedParams["previousPresent"];
    pointCut.proceed();
    SensorsDataAPI.getInstance().didRemove(target.route, previousPresent);
  }

  ///dialog 页面浏览 hook
  @Execute("package:flutter/src/widgets/routes.dart",
      "_DialogRoute", "-buildPage")
  @pragma("vm:entry-point")
  dynamic _trackDialogViewScreen1226(PointCut pointCut) {
    Route target = pointCut.target as Route<dynamic>;
    dynamic widgetResult = pointCut.proceed();
    SensorsDataAPI.getInstance().trackViewScreen(
        target, widgetResult, pointCut.positionalParams[0]);
    return widgetResult;
  }

  ///dialog 页面浏览 hook
  @Execute("package:flutter/src/widgets/routes.dart",
      "RawDialogRoute", "-buildPage")
  @pragma("vm:entry-point")
  dynamic _trackDialogViewScreen(PointCut pointCut) {
    Route target = pointCut.target as Route<dynamic>;
    dynamic widgetResult = pointCut.proceed();
    SensorsDataAPI.getInstance().trackViewScreen(
        target, widgetResult, pointCut.positionalParams[0]);
    return widgetResult;
  }

  @Execute("package:flutter/src/cupertino/route.dart",
      "CupertinoModalPopupRoute", "-buildPage")
  @pragma("vm:entry-point")
  dynamic _trackCupertinoDialogViewScreen(PointCut pointCut) {
    dynamic target = pointCut.target;
    dynamic context = pointCut.positionalParams[0];
    dynamic widgetResult = pointCut.proceed();
    dynamic realWidget = target.builder(context);
    SensorsDataAPI.getInstance().trackViewScreen(
        target, realWidget, pointCut.positionalParams[0]);
    return widgetResult;
  }

  @Execute("package:flutter/src/cupertino/route.dart",
      "_CupertinoModalPopupRoute", "-buildPage")
  @pragma("vm:entry-point")
  dynamic _trackCupertinoDialogViewScreenPrivate(PointCut pointCut) {
    dynamic target = pointCut.target;
    dynamic context = pointCut.positionalParams[0];
    dynamic widgetResult = pointCut.proceed();
    dynamic realWidget = target.builder(context);
    SensorsDataAPI.getInstance().trackViewScreen(
        target, realWidget, pointCut.positionalParams[0]);
    return widgetResult;
  }

  ///适配 PageRouteBuilder
  ///目前发现当 hook PageRouteBuilder 的时候，具体使用 material、cupertio 对应的 route，
  ///与谁先 hook 有关系，应该是 AspectD 的一个 bug
  ///TODO 此作为已知问题进行推进
  @Execute("package:flutter/src/widgets/pages.dart",
      "PageRouteBuilder", "-buildPage")
  @pragma("vm:entry-point")
  dynamic _trackPageRouteViewScreen(PointCut pointCut) {
    Route target = pointCut.target as Route<dynamic>;
    dynamic widgetResult = pointCut.proceed();
    SensorsDataAPI.getInstance().trackViewScreen(
        target, widgetResult, pointCut.positionalParams[0]);
    return widgetResult;
  }

  @Execute("package:flutter/src/material/page.dart",
      "MaterialRouteTransitionMixin", "-buildPage")
  @pragma("vm:entry-point")
  dynamic _trackViewScreen(PointCut pointCut) {
    Route target = pointCut.target as Route<dynamic>;
    dynamic widgetResult = pointCut.proceed();
    SensorsDataAPI.getInstance().trackViewScreen(
        target, widgetResult, pointCut.positionalParams[0]);
    return widgetResult;
  }

  ///适配 cupertino widget
  @Execute("package:flutter/src/cupertino/route.dart",
      "CupertinoRouteTransitionMixin", "-buildPage")
  @pragma("vm:entry-point")
  dynamic _trackCupertinoViewScreen(PointCut pointCut) {
    Route target = pointCut.target as Route<dynamic>;
    dynamic widgetResult = pointCut.proceed();
    SensorsDataAPI.getInstance().trackViewScreen(
        target, widgetResult, pointCut.positionalParams[0]);
    return widgetResult;
  }

  @Execute("package:flutter/src/material/tabs.dart", "_TabBarState",
      "-_handleTabControllerTick")
  // @Inject("package:flutter/src/material/tabs.dart", "_TabBarState",
  //         "-_handleTabControllerTick",lineNum: 987)
  @pragma("vm:entry-point")
  void _trackTabViewScreen(PointCut pointCut) {
    dynamic target = pointCut.target;
    dynamic widget = target.widget;
    final TabController controller =
        widget.controller ?? DefaultTabController.of(target.context)!;
    pointCut.proceed();
    print("=======${controller.index}");
    SensorsDataAPI.getInstance().trackTabViewScreen(target.widget,
        target.context,
        controller.index,
        target.widget.tabs[controller.index]);
  }

  ///BottomNavigationBar 页面浏览事件
  @Execute("package:flutter/src/material/bottom_navigation_bar.dart", "_BottomNavigationBarState",
      "-_rebuild")
  @pragma("vm:entry-point")
  void _trackBottomNavigationViewScreen(PointCut pointCut) {
    dynamic target = pointCut.target;
    pointCut.proceed();
    SensorsDataAPI.getInstance().trackBottomNavigationBarViewScreen(target.widget);
  }

  @Execute("package:flutter/src/gestures/binding.dart", "GestureBinding",
      "-dispatchEvent")
  @pragma("vm:entry-point")
  dynamic _trackHitTest(PointCut pointCut) {
    dynamic hitTestResult = pointCut.positionalParams[1];
    dynamic pointEvent = pointCut.positionalParams[0];
    if (pointEvent is PointerUpEvent) {
      //flutter 2.2.0 后 TextSpan 实现了 HitTestTarget 接口，如果直接转换成 RenderObject 会有问题
      for (final HitTestEntry entry in hitTestResult.path){
        if(entry.target is RenderObject){
          SensorsDataAPI.getInstance().trackHitTest(entry, pointEvent);
          break;
        }
      }
    }
    return pointCut.proceed();
  }

  @Execute("package:flutter/src/gestures/recognizer.dart", "GestureRecognizer",
      "-invokeCallback")
  @pragma("vm:entry-point")
  dynamic _trackClick(PointCut pointCut) {
    dynamic result = pointCut.proceed();
    dynamic eventName = pointCut.positionalParams[0];
    SensorsDataAPI.getInstance().trackClick(eventName);
    return result;
  }

  @Execute("package:flutter/src/widgets/framework.dart", "RenderObjectElement",
      "-mount")
  @pragma('vm:entry-point')
  void _hookElementMount(PointCut pointCut) {
    Element element = pointCut.target as Element;
    pointCut.proceed();
    if (kReleaseMode) {
      element.renderObject!.debugCreator = DebugCreator(element);
    }
  }

  @Execute('package:flutter/src/widgets/framework.dart', 'RenderObjectElement',
      '-update')
  @pragma('vm:entry-point')
  void _hookElementUpdate(PointCut pointCut) {
    Element element = pointCut.target as Element;
    pointCut.proceed();
    if (kReleaseMode) {
      element.renderObject!.debugCreator = DebugCreator(element);
    }
  }

  ///初始化一个 frame callback，用于获取刷新的时机
  @Execute('package:flutter/src/rendering/binding.dart', 'RendererBinding',
      '-initInstances')
  @pragma('vm:entry-point')
  void _hookRendererBinding(PointCut pointcut){
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
