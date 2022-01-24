import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:sensors_analytics_flutter_plugin/sensors_analytics_autotrack.dart';
import 'package:sensors_analytics_flutter_plugin/sensors_analytics_flutter_plugin.dart';

@pragma("vm:entry-point")
class SensorsDataAPI {
  static const String FLUTTER_AUTOTRACK_VERSION = "1.0.5";
  static final _instance = SensorsDataAPI._();

  ///判断是否已经添加了版本号 $lib_plugin_version
  bool hasAddedFlutterPluginVersion = false;
  var _deviceInfoMap = <String, Object>{};
  ViewScreenEvent? _lastViewScreen;

  //ViewScreenEvent _lastTabViewScreen;

  //route 相关的变量
  Route? _viewScreenRoute;
  Widget? _viewScreenWidget;
  BuildContext? _viewScreenContext;

  //存放页面浏览时的相关信息
  var _viewScreenCache = <Route?, _ViewScreenCache>{};
  var appBarTitle;
  var appTitleWidget;

  ///route 生命周期回调的时候记录路由信息，然后在 buildPage 之后获取 page 信息
  Route? _tryRoute;

  //tabbar 相关的变量
  Widget? _tabBarWidget;
  Widget? _tabWidget;
  BuildContext? _tabContext;
  int? _tabSelectedIndex;
  bool _tabShouldUpdate = false;
  Element? _tabWidgetElement;

  ///用于存放对应的路由和页面浏览事件
  var _routeViewScreenMap = <Route?, ViewScreenEvent>{};
  LastRoute? _lastRouteStatus;
  bool _isReplaceRoute = false;

  var _tabIndexMap = <BuildContext?, int>{};
  var _lastClickContent;

  ///BottomNavigationBar 使用
  Timer? _timer;

  SensorsDataAPI._() {
    _deviceInfoMap["os"] = Platform.operatingSystem;
    _deviceInfoMap["os_version"] = Platform.operatingSystemVersion;
    _deviceInfoMap["flutter_version"] = Platform.version;
  }

  factory SensorsDataAPI.getInstance() => _instance;

  ////////////////////////// view screen start
  ///触发路由页面浏览事件

  void updateRoute() {}

  void didPush(Route? route, Route? previousRoute) {
    SaLogger.p("==didpush2===${route}====${previousRoute}");

    if (_lastRouteStatus != null &&
        _lastRouteStatus!.routeStatus == RouteStatus.pop) {
      _routeViewScreenMap.remove(_lastRouteStatus!.route);
      SaLogger.p("delete lastRoute=====${_lastRouteStatus}");
    }
    _lastRouteStatus = null;

    _tryRoute = route;
    //push 情况需要直接触发新的页面浏览事件，是否要考虑多次 push 的情况
    //_printViewScreenMap();
  }

  void didPop(Route? route, Route? previousRoute) {
    SaLogger.p("==didPop2===${route}====${previousRoute}");
    if (_lastRouteStatus != null) {
      _routeViewScreenMap.remove(_lastRouteStatus!.route);
    }

    _lastRouteStatus = LastRoute();
    _lastRouteStatus!.routeStatus = RouteStatus.pop;
    _lastRouteStatus!.route = route;
    _lastRouteStatus!.previousRoute = previousRoute;

    //_printViewScreenMap();
    //1.如果是 popAndPush，此处应该只是移除
    //2.如果是 popUntil，此处应该只记录最后一个
  }

  void didReplace(Route? newRoute, Route? oldRoute) {
    SaLogger.p("==didReplace2===${newRoute}====${oldRoute}");
    _routeViewScreenMap.remove(oldRoute);
    _tryRoute = newRoute;
    _isReplaceRoute = true;
    //replace 需要直接触发新的页面路由的页面浏览事件
    //_printViewScreenMap();
  }

  void didRemove(Route? route, Route? previousRoute) {
    if (!_isReplaceRoute) {
      SaLogger.p(
          "==didRemove2===${route}====${previousRoute}===$_isReplaceRoute");
      //此处要删除 route 中的所有路由，不用管 previousRoute
      _routeViewScreenMap.remove(route);
      //_printViewScreenMap();
    }
  }

  ///通过 [SchedulerBinding.instance?.addPersistentFrameCallback] 添加的回调
  void persistentFrameCallback(Duration timeStamp) {
    //SaLogger.p("persistent frame callback====");
    //在此处恢复状态为 none
    if (_lastRouteStatus != null &&
        _lastRouteStatus!.routeStatus == RouteStatus.pop) {
      //_printViewScreenMap();
      _routeViewScreenMap.remove(_lastRouteStatus!.route);
      ViewScreenEvent? screenEvent =
          _routeViewScreenMap[_lastRouteStatus!.previousRoute];
      if (screenEvent != null) {
        _lastViewScreen = screenEvent;
        _printViewScreen(screenEvent);
        Map map = screenEvent.toSDKMap()!;
        SensorsAnalyticsFlutterPlugin.trackViewScreen(
            map[r"$screen_name"], map as Map<String, dynamic>?);
        _resetViewScreen();
      }
    }
    _lastRouteStatus = null;
    _isReplaceRoute = false;

    _internalUpdateRoute();
    _internalTabUpdate();
  }

  void _internalUpdateRoute() {
    //将缓存中的数据清空，并触发页面浏览事件
    _viewScreenCache.removeWhere((Route? route, _ViewScreenCache screenCache) {
      if (route != null && screenCache._viewScreenContext != null) {
        SaLogger.p("===internalUpdateRoute====$route");
        _lastViewScreen = null;
        appTitleWidget = null;
        appBarTitle = null;

        _viewScreenRoute = screenCache._viewScreenRoute;
        _viewScreenWidget = screenCache._viewScreenWidget;
        _viewScreenContext = screenCache._viewScreenContext;

        //Fix:Flutter Modular 2.x
        if (_viewScreenWidget.runtimeType.toString() == '_DisposableWidget') {
          dynamic tmp = _viewScreenWidget;
          _viewScreenWidget = tmp.child(_viewScreenContext, null);
        }

        ViewScreenEvent screenEvent = ViewScreenEvent();
        if (_viewScreenWidget is _SAHasCreationLocation) {
          _SAHasCreationLocation location =
              _viewScreenWidget as _SAHasCreationLocation;
          //SaLogger.p("====>viewscreen location===${location?._salocation}");
          if (location._salocation.file != null) {
            screenEvent.fileName = location._salocation.file!
                .replaceAll(location._salocation.rootUrl!, "");
          }
          screenEvent.importUri = location._salocation.importUri;
        }

        _findAppBar(_viewScreenContext as Element?);
        if (appBarTitle != null) {
          screenEvent.title = appBarTitle;
        }
        screenEvent.routeName = _viewScreenRoute?.settings?.name;
        screenEvent.widgetName = _viewScreenWidget?.runtimeType.toString();
        //需要确认 screenEvent page file url 如何获取
        _lastViewScreen = screenEvent;
        _printViewScreen(screenEvent);
        _setupLibPluginVersion();
        _checkViewScreenImpl(screenEvent);
        Map map = screenEvent.toSDKMap()!;
        SensorsAnalyticsFlutterPlugin.trackViewScreen(
            map[r"$url"] ?? map[r"$screen_name"],
            map as Map<String, dynamic>?);
        _routeViewScreenMap[_viewScreenRoute] = screenEvent;
        _tabIndexMap.clear();
        _resetViewScreen();
      }
      return true;
    });
  }

  ///触发 tab 页页面浏览事件
  void _internalTabUpdate() {
    if (!_tabShouldUpdate) {
      return;
    }
    ViewScreenEvent screenEvent = ViewScreenEvent();
    if (_tabWidget is _SAHasCreationLocation) {
      _SAHasCreationLocation location = _tabWidget as _SAHasCreationLocation;
      SaLogger.p("====>viewscreen location tab===${location._salocation}");
      screenEvent.fileName = location._salocation.file!
          .replaceAll(location._salocation.rootUrl!, "");
      screenEvent.importUri = location._salocation.importUri;
    }
    _findTargetTabWidget(_tabContext as Element?);
    if (contentText != null) {
      screenEvent.title = "$contentText";
    }
    screenEvent.widgetName = _tabBarWidget.runtimeType.toString();
    screenEvent.routeName = _lastViewScreen?.routeName;
    _lastViewScreen = screenEvent;
    _printViewScreen(screenEvent, {"tab_index": _tabSelectedIndex});
    Map map = screenEvent.toSDKMap()!;
    _setupLibPluginVersion();
    SensorsAnalyticsFlutterPlugin.trackViewScreen(
        map[r"$screen_name"], map as Map<String, dynamic>?);
    _resetViewScreen();
  }

  ///添加带有 route 的页面浏览事件
  ///此方法是在插件中调用
  void trackViewScreen(Route route, Widget? widget, BuildContext? context) {
    SaLogger.p("====trackViewScreen===${route}===${widget}");
    if (_tryRoute == null || _tryRoute != route) {
      return;
    }

    Widget? _viewScreenWidget = widget;
    //如果是对话框路由
    //TODO 应该获取第一个自己创建的 Widget
    String routeWidgetName = route.runtimeType.toString();
    if (route is PopupRoute) {
      //print("====111===${routeWidgetName}");
      if (routeWidgetName.startsWith('CupertinoDialogRoute<') ||
          routeWidgetName.startsWith('CupertinoModalPopupRoute<') ||
          routeWidgetName.startsWith('_CupertinoModalPopupRoute<')) {
        if (widget is Semantics) {
          _viewScreenWidget = widget.child;
        } else {
          _viewScreenWidget = widget;
        }
      }
      //对于 RawDialogRoute 比较麻烦，其内部做了很多的 wrap，所以要拿到真实的 Widget，就需要一步一步来操作
      else {
        if ((routeWidgetName.startsWith('DialogRoute<') ||
                routeWidgetName.startsWith('_DialogRoute<') ||
                routeWidgetName.startsWith('RawDialogRoute<')) &&
            widget is Semantics) {
          try {
            dynamic tmpWidget = widget.child;
            //print("====2222===${tmpWidget}");
            if (tmpWidget is SafeArea) {
              tmpWidget = tmpWidget.child;
            }
            //wrap 情况
            if (tmpWidget.runtimeType.toString() == '_CaptureAll') {
              tmpWidget = tmpWidget.child;
            }
            //此时应该是 builder
            if (tmpWidget is Builder) {
              tmpWidget = tmpWidget.build(context!);
              //print("====33333===${tmpWidget}");
            }
            _viewScreenWidget = tmpWidget;
          } catch (e, s) {
            _viewScreenWidget = widget;
          }
        } else {
          _viewScreenWidget = widget;
        }
      }
    }
    //因为 aspectd  AOP 处理 PageRouteBuilder 存在问题，这里做一个判断，将逻辑放在这里
    else if ((route is CupertinoRouteTransitionMixin ||
            route is MaterialRouteTransitionMixin) &&
        widget is Semantics) {
      _viewScreenWidget = widget.child;
    } else {
      if (routeWidgetName.startsWith("GetPageRoute<")) {
        _SAHasCreationLocation tmp = widget as _SAHasCreationLocation;
        if (tmp._salocation.isProjectRoot()) {
          _viewScreenWidget = widget;
        } else if (widget is Semantics) {
          _viewScreenWidget = widget.child;
        } else {
          _viewScreenWidget = widget;
        }
      } else {
        _viewScreenWidget = widget;
      }
    }

    _ViewScreenCache screenCache = _ViewScreenCache();
    screenCache._viewScreenWidget = _viewScreenWidget;
    screenCache._viewScreenRoute = _tryRoute;
    screenCache._viewScreenContext = context;
    _viewScreenCache[_tryRoute] = screenCache;

    _tryRoute = null;

    SaLogger.p("====trackViewScreen===inner====$screenCache");
  }

  void popRemove(Route route, Route previousRoute) {
    //[优化]需要处理返回的时候页面浏览
  }

  void pushReplace(Route route, Route previousRoute) {}

  void trackTabViewScreen(
      Widget? widget, BuildContext? context, int index, Widget? tab) {
    int? currentIndex = _tabIndexMap[context];
    if (currentIndex != null && currentIndex == index) {
      SaLogger.d("same tab[$index], do nothing");
      return;
    } else {
      _tabIndexMap[context] = index;
    }

    _tabBarWidget = widget;
    _tabContext = context;
    _tabWidget = tab;
    _tabSelectedIndex = index;
    _tabShouldUpdate = true;
  }

  void _findTargetTabWidget(Element? element) {
    if (_tabWidgetElement != null) {
      return;
    }
    if (element!.widget == _tabWidget) {
      _tabWidgetElement = element;
      _searchDownElementContent(_tabWidgetElement);
      return;
    }
    element.visitChildElements(_findTargetTabWidget);
  }

  ///根据 Element 查找 Scaffold，再获取 AppBar 中的 title 信息
  void _findAppBar(Element? context) {
    if (appBarTitle != null || appTitleWidget != null) {
      return;
    }
    if (context!.widget is Scaffold) {
      Scaffold scaffold = context.widget as Scaffold;
      PreferredSizeWidget? appBar = scaffold.appBar;
      //如果没有 appbar，就直接返回，对应的title就是空
      if (appBar == null) {
        return;
      }
      if (appBar is AppBar) {
        appTitleWidget = appBar.title;
      }
      if (appTitleWidget != null && appTitleWidget is Text) {
        appBarTitle = appTitleWidget.data;
      } else {
        _getAppBar(context);
      }
      return;
    }
    context.visitChildElements(_findAppBar);
  }

  void _getAppBar(Element element) {
    if (element.widget is AppBar) {
      appTitleWidget = (element.widget as AppBar).title;
    }
    if (element.widget == appTitleWidget) {
      _getElementContentByType(element);
      if (contentList.isNotEmpty) {
        String result = contentList.join("-");
        appBarTitle = result;
      }
    } else {
      element.visitChildElements(_getAppBar);
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

  ///清除临时变量
  void _resetViewScreen() {
    this._tryRoute = null;
    this._viewScreenRoute = null;
    this._viewScreenWidget = null;
    this._viewScreenContext = null;
    this.appBarTitle = null;

    this._tabBarWidget = null;
    this._tabContext = null;
    this._tabWidget = null;
    this._tabSelectedIndex = -1;
    this._tabShouldUpdate = false;
    this._tabWidgetElement = null;
    this.contentText = null;

    contentList.clear();
  }

  ////////////////////////// view screen end
  ////////////////////////// view click start

  var _curPointerCode = -1;
  var _prePointerCode = -1;
  var clickRenderMap = <int, RenderObject>{}; //基于此可以获得路径信息
  var currentEvent;
  late HitTestEntry hitTestEntry;
  var elementInfoMap = <String, dynamic>{};
  String? contentText;
  bool searchStop = false;

  ///采集 element_type 时对应的 element
  Element? elementTypeElement;
  var elementPathList = <Element>[];

  ///用于拼装 element content
  List<String> contentList = [];
  List<String> bottomBarContentList = [];

  ///element type 对应的 widget
  var elementTypeWidget;

  void trackHitTest(HitTestEntry entry, PointerEvent event) {
    currentEvent = event;
    hitTestEntry = entry;
    var target = entry.target;
    _curPointerCode = event.pointer;
    if (target is RenderObject) {
      if (_curPointerCode > _prePointerCode) {
        clickRenderMap.clear();
      }
      clickRenderMap[_curPointerCode] = target;
    }
    _prePointerCode = _curPointerCode;
  }

  void trackClick(String? eventName) {
    if (eventName == "onTap") {
      elementPathList.clear();
      contentText = null;
      searchStop = false;
      elementInfoMap.clear();
      elementTypeWidget = null;
      _getElementPath();
      _getElementType();
      if (!_isIgnoreClick()) {
        _wrapElementContent();
        _setupClickEventScreenInfo();
        _printClick(elementInfoMap);
        //elementInfoMap.removeWhere((key, value) => value == null);
        elementInfoMap[r"$lib_method"] = "autoTrack";
        _calculateListPosition();
        _setupLibPluginVersion();
        SensorsAnalyticsFlutterPlugin.track(r"$AppClick", elementInfoMap);
      }
      _resetAppClick();
    }
  }

  void _resetAppClick() {
    elementPathList.clear();
    contentText = null;
    searchStop = false;
    elementInfoMap.clear();
    elementTypeWidget = null;
    contentList.clear();
    elementTypeElement = null;
  }

  ///触发 BottomNavigationBar 的页面浏览事件

  void trackBottomNavigationBarViewScreen(
      BottomNavigationBar? navigationBar, BuildContext context) {
    if (_timer != null && _timer!.isActive) {
      _timer!.cancel();
    }
    _timer = Timer(Duration(milliseconds: 100), () {
      ViewScreenEvent viewScreenEvent = ViewScreenEvent();
      Widget? _viewScreenWidget = navigationBar;
      if (_viewScreenWidget is _SAHasCreationLocation) {
        _SAHasCreationLocation location =
            _viewScreenWidget as _SAHasCreationLocation;
        if (location._salocation.file != null) {
          viewScreenEvent.fileName = location._salocation.file!
              .replaceAll(location._salocation.rootUrl!, "");
        }
        viewScreenEvent.importUri = location._salocation.importUri;
      }
      String? clickContent;
      bottomBarContentList.clear();
      clickContent = navigationBar!.items[navigationBar.currentIndex].label;
      if (clickContent == null) {
        appBarTitle = null;
        appTitleWidget = navigationBar.items[navigationBar.currentIndex].title;
        _getBottomNavigationBarWidget(context as Element);
        clickContent = appBarTitle;
      }
      if (clickContent == null) {
        clickContent = navigationBar.items[navigationBar.currentIndex].tooltip;
      }
      viewScreenEvent.title = clickContent;
      viewScreenEvent.widgetName = "BottomNavigationBar";
      viewScreenEvent.routeName = _lastViewScreen?.routeName;
      _printViewScreen(viewScreenEvent);
      _lastViewScreen = viewScreenEvent;
      Map map = viewScreenEvent.toSDKMap()!;
      SensorsAnalyticsFlutterPlugin.trackViewScreen(
          map[r"$screen_name"], map as Map<String, dynamic>?);
    });
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

  ///用来计算 Element 在 ListView, GridView 中的位置，既 $element_position 的值
  ///只有父节点中是 SliverMultiBoxAdaptorElement 的 Widget 才会存在该值
  void _calculateListPosition() {
    int? previousSlot;
    int? lastPossiblePosition;
    elementPathList.first.visitAncestorElements((element) {
      if (element is SliverMultiBoxAdaptorElement &&
          (element.widget is SliverList || element.widget is SliverGrid)) {
        lastPossiblePosition = previousSlot;
        return false;
      }
      if (element.slot != null) {
        if (element.slot is IndexedSlot) {
          previousSlot = (element.slot as IndexedSlot).index;
        } else if (element.slot is int) {
          previousSlot = element.slot as int?;
        }
      }
      return true;
    });
    if (lastPossiblePosition != null) {
      elementInfoMap[r"$element_position"] = "$lastPossiblePosition";
    }
  }

  ///如果修改此方法，记得一定要修改 getElementType
  void _wrapElementContent() {
    RenderObject renderObject = hitTestEntry.target as RenderObject;
    DebugCreator debugCreator = renderObject.debugCreator as DebugCreator;
    Element element = debugCreator.element;
    //
    Element? finalContainerElement;
    element.visitAncestorElements((element) {
      String? finalResult;
      dynamic widget = element.widget;
      //针对泛型类型，避免 is 关键字添加
      dynamic dynamicWidget = widget;
      if (widget is RaisedButton && _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is FlatButton && _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is FloatingActionButton &&
          _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is BottomNavigationBar && _checkOnTabNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is GestureDetector && _checkOnTabNull(widget)) {
        finalResult = widget.child.runtimeType.toString();
      } else if (widget is ListTile && _checkOnTabNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is PopupMenuButton &&
          dynamicWidget.onSelected != null) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is PopupMenuButton && _checkOnSelectedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is OutlineButton && _checkOnPressedNull(widget)) {
        finalResult = "OutlineButton";
      } else if (widget is InkWell && _checkOnTabNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is BottomNavigationBar && _checkOnTabNull(widget)) {
        finalResult = widget.runtimeType.toString();
      }
      //新增部分
      else if (widget is BackButton && _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is CloseButton && _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is CupertinoButton && _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is RawMaterialButton && _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is DropdownMenuItem) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is DropdownButton &&
          (_checkOnChangedNull(widget) || _checkOnTabNull(widget))) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is CheckboxListTile && _checkOnChangedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is Checkbox && _checkOnChangedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is PopupMenuItem) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is CheckedPopupMenuItem) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is InputChip &&
          (_checkOnPressedNull(widget) || _checkOnSelectedNull(widget))) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is RawChip &&
          (_checkOnPressedNull(widget) || _checkOnSelectedNull(widget))) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is ChoiceChip && _checkOnSelectedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is FilterChip && _checkOnSelectedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is ActionChip && _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is CupertinoActionSheetAction &&
          _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is CupertinoContextMenuAction &&
          _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is Radio && _checkOnChangedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is RadioListTile && _checkOnChangedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is SnackBarAction && _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is Switch && _checkOnChangedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is SwitchListTile && _checkOnChangedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is CupertinoSwitch && _checkOnChangedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is ToggleButtons && _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is CupertinoContextMenuAction &&
          _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      }

      if (finalResult != null) {
        finalContainerElement = element;
        return false;
      }
      return true;
    });

    if (finalContainerElement == null &&
        (element.widget is Text || element.widget is RichText)) {
      finalContainerElement = element;
    }

    if (finalContainerElement != null) {
      SaLogger.i("可能的 wrapper element===> $element，如果采集的 content 不准确，请联系我");
      _getElementContentByType(finalContainerElement);
      if (contentList.isNotEmpty) {
        String result = contentList.join("-");
        elementInfoMap[r"$element_content"] = result;
      }
    } else {
      SaLogger.i("未找到 wrapper element，联系我适配，当前的 element 是: $element");
    }
  }

  ///通过 element_type 查找对应 element 下的所有
  ///通过先序遍历的方式，如果对应的节点上获取到了文本就返回
  void _getElementContentByType(Element? element) {
    if (element != null) {
      //元素内容

      String? tmp = try2GetText(element.widget);
      if (tmp != null) {
        contentList.add(tmp);
        return;
      }

      element.visitChildElements(_getElementContentByType);
    }
  }

  void _getBottomAppBarElementContentByType(Element? element) {
    if (element != null) {
      String? tmp = try2GetText(element.widget);
      if (tmp != null) {
        bottomBarContentList.add(tmp);
        return;
      }
      element.visitChildElements(_getBottomAppBarElementContentByType);
    }
  }

  ///向下搜索元素内容
  void _searchDownElementContent(Element? element) {
    if (searchStop) {
      return;
    }
    if (contentText != null) {
      return;
    }
    checkText(element!.widget);
    if (contentText != null) {
      return;
    }
    //如果有多个兄弟节点，那么就去先去从兄弟节点查找
    if (element is MultiChildRenderObjectElement) {
      //采用反转遍历的方式来查找
      List<Element> list = element.children.toList();
      if (list.isNotEmpty) {
        for (int index = list.length - 1; index >= 0; index--) {
          if (contentText != null) {
            return;
          }
          checkText(list[index].widget);
          if (contentText != null) {
            return;
          }
          list[index].visitChildElements(_searchDownElementContent);
        }
      }
    } else {
      element.visitChildElements(_searchDownElementContent);
    }
  }

  ///向上搜索元素内容，向上搜索以遇到的第一个 GestureDector 为结束点，如果找不到就停止向上遍历
  void _searchUpElementContent(Element element) {
    if (contentText != null) {
      return;
    }
    checkText(element.widget);
    if (contentText != null) {
      return;
    }
    //找到第一个 elementType 就停止
    if (element == elementTypeWidget) {
      searchStop = true;
      return;
    }

    //获取父节点
    element.visitAncestorElements((parentElement) {
      if (searchStop) {
        return false;
      }
      if (parentElement.widget == elementTypeWidget ||
          element.widget == elementTypeWidget) {
        searchStop = true;
        return false;
      }
      checkText(parentElement.widget);
      if (contentText != null) {
        return false;
      }

      //如果父节点有多个子节点，依次遍历子节点，可能会向下遍历，但不包括其自身节点
      if (parentElement is MultiChildRenderObjectElement) {
        List<Element> list = parentElement.children.toList();
        if (list.isNotEmpty) {
          for (int index = list.length - 1; index >= 0; index--) {
            if (searchStop) {
              return false;
            }
            //不包括其自身
            if (list[index] != parentElement) {
              checkText(list[index].widget);
              if (contentText != null) {
                break;
              }
              list[index].visitChildElements(_searchDownElementContent);
            }
          }
        }
      }
      //如果已经获取到了，那么就不在处理
      if (contentText != null) {
        return false;
      }
      return true;
    });
  }

  void checkSpecialWidget(Element element) {
    //Switch
    if (element.widget.runtimeType.toString() == "_SwitchRenderObjectWidget") {
      searchStop = true;
      elementInfoMap[r"$element_type"] = "Switch";
    }
    //CheckBox
    else if (element.widget.runtimeType.toString() ==
        "_CheckboxRenderObjectWidget") {
      searchStop = true;
      elementInfoMap[r"$element_type"] = "CheckBox";
    }
  }

  ///检测是否是能够显示文字的组件，如果是的话，就获取其对应的值
  void checkText(Widget widget) {
    String? result;
    if (widget is Text) {
      result = widget.data;
    } else if (widget is RichText) {
      //针对 RichText 进行处理，因为 Icon 这个 Widget 使用的是 RichText 来实现的。
      RichText tmp = widget;
      var tmp1 = tmp.toString();
      if (tmp.text is TextSpan) {
        TextSpan textSpan = tmp.text as TextSpan;
        try {
          String? fontFamily = textSpan.style?.fontFamily;
          //对于系统提供的 Icon，其 family 都是统一的 MaterialIcons，当出现这种情况的时候就认为没有采集到文字信息，采集平级或者向上去找文字信息
          if (fontFamily != "MaterialIcons") {
            result = textSpan.toPlainText();
          }
        } catch(e) {
          result = textSpan.toPlainText();
        }
      }
    } else if (widget is Tooltip) {
      result = widget.message;
    } else if (widget is Tab) {
      result = widget.text;
    } else if (widget is IconButton) {
      result = widget.tooltip ?? "";
    }
    contentText = result;
  }

  ///尝试获取 Widget 对应的文本，一定要和 [checkText] 这个方法对应起来
  String? try2GetText(Widget widget) {
    String? result;
    if (widget is Text) {
      result = widget.data;
    } else if (widget is RichText) {
      //针对 RichText 进行处理，因为 Icon 这个 Widget 使用的是 RichText 来实现的。
      RichText tmp = widget;
      var tmp1 = tmp.toString();
      if (tmp.text is TextSpan) {
        TextSpan textSpan = tmp.text as TextSpan;
        String? fontFamily = textSpan.style?.fontFamily;
        //对于系统提供的 Icon，其 family 都是统一的 MaterialIcons，当出现这种情况的时候就认为没有采集到文字信息，采集平级或者向上去找文字信息
        if (fontFamily != "MaterialIcons") {
          result = textSpan.toPlainText();
        }
      }
    } else if (widget is Tooltip) {
      result = widget.message;
    } else if (widget is Tab) {
      result = widget.text;
    } else if (widget is IconButton) {
      result = widget.tooltip ?? "";
    }
    return result;
  }

  bool _shouldAddToPath(Element element) {
    Widget widget = element.widget;
    if (widget is _SAHasCreationLocation) {
      _SAHasCreationLocation creationLocation =
          widget as _SAHasCreationLocation;
      if (creationLocation._salocation != null) {
        return creationLocation._salocation.isProjectRoot();
      }
    }
    return false;
  }

  /// 用于显示和 flutter inspector 上类似的路径
  void _getElementPath() {
    var listResult = <String>[];
    print("start to getlement path===");
    RenderObject renderObject = hitTestEntry.target as RenderObject;
    DebugCreator debugCreator = renderObject.debugCreator as DebugCreator;

    print("renderObject===${renderObject}");
    print("debugCreator===${debugCreator}");

    Element element = debugCreator.element;
    print("element===${element}");

    if (_shouldAddToPath(element)) {
      var result = "${element.widget.runtimeType.toString()}";
      int slot = 0;
      if (element.slot != null) {
        if (element.slot is IndexedSlot) {
          slot = (element.slot as IndexedSlot).index;
        }
      }
      result += "[$slot]";
      listResult.add(result);
      elementPathList.add(element);
    }

    element.visitAncestorElements((element) {
      if (_shouldAddToPath(element)) {
        var result = "${element.widget.runtimeType.toString()}";
        int slot = 0;
        if (element.slot != null) {
          if (element.slot is IndexedSlot) {
            slot = (element.slot as IndexedSlot).index;
          }
        }
        result += "[$slot]";
        listResult.add(result);
        elementPathList.add(element);
      }
      return true;
    });
    String finalResult = "";
    listResult.reversed.forEach((element) {
      finalResult += "/$element";
    });

    if (finalResult.startsWith('/')) {
      finalResult = finalResult.replaceFirst('/', '');
    }
    elementInfoMap[r"$element_path"] = finalResult;
  }

  ///用于判断当前的 click 是否有必要进行忽略
  bool _isIgnoreClick() {
    if (elementTypeElement != null) {
      Widget widget = elementTypeElement!.widget;
      if (widget is BackButton && widget.onPressed == null) {
        return true;
      } else if (widget is CloseButton && widget.onPressed == null) {
        return true;
      } else if (widget is ListTile && widget.onTap == null) {
        return true;
      } else if (widget is RawMaterialButton && widget.onPressed == null) {
        return true;
      } else if (widget is CupertinoContextMenuAction &&
          widget.onPressed == null) {
        return true;
      }
    }
    return false;
  }

  ///如果修改此方法，记得一定要修改 _wrapElementContent
  void _getElementType() {
    if (elementPathList.isEmpty) {
      return;
    }
    String? finalResult;
    String? maybeContent;
    bool reSearchContent = false;

    for (Element element in elementPathList) {
      Widget widget = element.widget;
      //针对泛型类型，避免 is 关键字添加
      dynamic dynamicWidget = widget;
      if (widget is RaisedButton && _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is FlatButton && _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is FloatingActionButton &&
          _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is BottomNavigationBar && _checkOnTabNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is GestureDetector && _checkOnTabNull(widget)) {
        finalResult = widget.child.runtimeType.toString();
      } else if (widget is ListTile && _checkOnTabNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is IconButton && _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
        maybeContent = widget.tooltip;
      } else if (widget is PopupMenuButton &&
          dynamicWidget.onSelected != null) {
        finalResult = widget.runtimeType.toString();
        maybeContent = widget.tooltip;
      } else if (widget is OutlineButton && _checkOnPressedNull(widget)) {
        finalResult = "OutlineButton";
      } else if (widget is InkWell && _checkOnTabNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is BottomNavigationBar && _checkOnTabNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is BottomNavigationBarItem) {
        finalResult = widget.runtimeType.toString();
      }
      //新增部分
      else if (widget is BackButton && _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is CloseButton && _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is CupertinoButton && _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is RawMaterialButton && _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is DropdownMenuItem) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is DropdownButton &&
          (_checkOnChangedNull(widget) || _checkOnTabNull(widget))) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is CheckboxListTile && _checkOnChangedNull(widget)) {
        finalResult = widget.runtimeType.toString();
        reSearchContent = true;
      } else if (widget is Checkbox && _checkOnChangedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is PopupMenuItem) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is CheckedPopupMenuItem) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is InputChip &&
          (_checkOnPressedNull(widget) || _checkOnSelectedNull(widget))) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is RawChip &&
          (_checkOnPressedNull(widget) || _checkOnSelectedNull(widget))) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is ChoiceChip && _checkOnSelectedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is FilterChip && _checkOnSelectedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is ActionChip && _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is CupertinoActionSheetAction &&
          _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is CupertinoContextMenuAction &&
          _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is Radio && _checkOnChangedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is RadioListTile && _checkOnChangedNull(widget)) {
        finalResult = widget.runtimeType.toString();
        reSearchContent = true;
      } else if (widget is SnackBarAction && _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is Switch && _checkOnChangedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is SwitchListTile && _checkOnChangedNull(widget)) {
        finalResult = widget.runtimeType.toString();
        reSearchContent = true;
      } else if (widget is CupertinoSwitch && _checkOnChangedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is ToggleButtons && _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      } else if (widget is CupertinoContextMenuAction &&
          _checkOnPressedNull(widget)) {
        finalResult = widget.runtimeType.toString();
      }

      if (finalResult != null) {
        elementTypeWidget = finalResult;
        elementTypeElement = element;
        break;
      }
    }
    if (finalResult == null) {
      //TODO 如果为空，可以尝试直接返回不支持
      SaLogger.w("未找到 element_type，将使用最后一个作为 element_type");
      finalResult = elementPathList[0].widget.runtimeType.toString();
      elementTypeElement = elementPathList[0];
    }

    elementTypeWidget = finalResult;
    elementInfoMap[r"$element_type"] = finalResult;
    if (maybeContent != null) {
      elementInfoMap[r"$element_content"] = maybeContent;
    }
    if (reSearchContent &&
        elementInfoMap[r"$element_content"] == null &&
        elementTypeElement != null) {
      _getElementContentByType(elementTypeElement);
      if (contentList.isNotEmpty) {
        String result = contentList.join("-");
        elementInfoMap[r"$element_content"] = result;
        contentList.clear(); //这里只是一个可能的结果，不能影响后面真正获取数据的操作
      }
    }
  }

  bool _checkOnChangedNull(dynamic widget) {
    return widget.onChanged != null;
  }

  bool _checkOnPressedNull(dynamic widget) {
    return widget.onPressed != null;
  }

  bool _checkOnSelectedNull(dynamic widget) {
    return widget.onSelected != null;
  }

  bool _checkOnTabNull(dynamic widget) {
    return widget.onTap != null;
  }

  void _setupClickEventScreenInfo() {
    // print(
    //     "_setupClickEventScreenInfo:  ${_lastTabViewScreen}===$_lastViewScreen");
    // if (_lastTabViewScreen != null) {
    //   if (elementPathList != null && elementPathList.isNotEmpty) {
    //     for (Element element in elementPathList) {
    //       //如果向上找到了外围的页面浏览事件对应的 widget，那么就直接退出循环
    //       if (element.widget.runtimeType.toString() == _lastViewScreen.widgetName) {
    //         break;
    //       }
    //       //如果其路径中由 TabBar 就认为其是
    //       if (element.widget is TabBar) {
    //         elementInfoMap.addAll(_lastTabViewScreen.toSDKMap());
    //         return;
    //       }
    //     }
    //   }
    // }

    if (_lastViewScreen != null) {
      elementInfoMap
          .addAll(_lastViewScreen!.toSDKMap(isClick: true) as Map<String, dynamic>);
    }
  }

  ///在触发的第一个事件中添加版本信息
  void _setupLibPluginVersion() {
    if (!hasAddedFlutterPluginVersion) {
      hasAddedFlutterPluginVersion = true;
      elementInfoMap[r"$lib_plugin_version"] = [
        "flutter:$FLUTTER_AUTOTRACK_VERSION"
      ];
    }
  }

  ///判断页面是否实现了 ISensorsDataViewScreen 接口
  void _checkViewScreenImpl(ViewScreenEvent viewScreenEvent) {
    if (_viewScreenWidget != null &&
        _viewScreenWidget is ISensorsDataViewScreen) {
      ISensorsDataViewScreen sensorsDataViewScreen =
          _viewScreenWidget as ISensorsDataViewScreen;
      try {
        viewScreenEvent.viewScreenName = sensorsDataViewScreen.viewScreenName;
      } catch (e) {
        viewScreenEvent.viewScreenName = null;
      }
      try {
        viewScreenEvent.viewScreenTitle = sensorsDataViewScreen.viewScreenTitle;
      } catch (e) {
        viewScreenEvent.viewScreenTitle = null;
      }
      try {
        viewScreenEvent.viewScreenUrl = sensorsDataViewScreen.viewScreenUrl;
      } catch (e) {
        viewScreenEvent.viewScreenUrl = null;
      }
      try {
        viewScreenEvent.trackProperties = sensorsDataViewScreen.trackProperties;
      } catch (e) {
        viewScreenEvent.trackProperties = null;
      }
    }
  }

  ////////////////////////// view click end

  void _printViewScreen(ViewScreenEvent event,
      [Map<String, Object?>? otherData]) {
    String result = "";
    result +=
        "\n========================================ViewScreen=======================================\n";
    result += event.toString() + "\n";
    _deviceInfoMap.forEach((key, value) {
      result += "$key: $value\n";
    });
    otherData?.forEach((key, value) {
      result += "$key: $value\n";
    });
    result +=
        "=========================================================================================";
    SaLogger.p(result);
  }

  void _printClick(Map<String, dynamic> otherData) {
    String result = "";
    result +=
        "\n==========================================Clicked========================================\n";
    _deviceInfoMap.forEach((key, value) {
      result += "$key: $value\n";
    });
    otherData.forEach((key, value) {
      result += "$key: $value\n";
    });
    result += "time: ${DateTime.now().toString()}\n";
    result +=
        "=========================================================================================";
    SaLogger.i(result);
  }

  ///打印 view screen 缓存中的数据
  void _printViewScreenMap() {
    SaLogger.p("start print view screen map");
    _routeViewScreenMap.forEach((key, value) {
      print("routeViewScreen===$key===${value}");
    });
    SaLogger.p("end print view screen map");
  }
}

@pragma("vm:entry-point")
class ViewScreenEvent {
  String? routeName;
  String? widgetName;
  String? fileName;
  String? importUri;
  String? title;

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
      } else{
        _sdkMap[r"$url"] = '$result/$widgetName';
      }
      if (trackProperties != null) {
        _sdkMap.addEntries(trackProperties!.entries);
      }
    }
    return _sdkMap;
  }
}

//用于保存 ViewScreen 需要的事件
@pragma("vm:entry-point")
class _ViewScreenCache {
  Route? _viewScreenRoute;
  Widget? _viewScreenWidget;
  BuildContext? _viewScreenContext;

  @override
  String toString() {
    return '_ViewScreenCache{_viewScreenRoute: $_viewScreenRoute, _viewScreenWidget: $_viewScreenWidget, _viewScreenContext: $_viewScreenContext}';
  }
}

///Location Part
@pragma("vm:entry-point")
abstract class _SAHasCreationLocation {
  _SALocation get _salocation;
}

@pragma("vm:entry-point")
class _SALocation {
  const _SALocation({
    this.file,
    this.rootUrl,
    this.importUri,
    this.line,
    this.column,
    this.name,
    this.parameterLocations,
  });

  final String? rootUrl;
  final String? importUri;
  final String? file;
  final int? line;
  final int? column;
  final String? name;
  final List<_SALocation>? parameterLocations;

  bool isProjectRoot() {
    if (rootUrl == null || file == null) {
      return false;
    }
    return file!.startsWith(rootUrl!);
  }

  Map<String, Object?> toJsonMap() {
    final Map<String, Object?> json = <String, Object?>{
      'file': file,
      'line': line,
      'column': column,
    };
    if (name != null) {
      json['name'] = name;
    }
    if (parameterLocations != null) {
      json['parameterLocations'] = parameterLocations!
          .map<Map<String, Object?>>(
              (_SALocation location) => location.toJsonMap())
          .toList();
    }
    return json;
  }

  @override
  String toString() {
    return '_SALocation{rootUrl: $rootUrl, importUri: $importUri, file: $file, line: $line, column: $column, name: $name, parameterLocations: $parameterLocations}';
  }
}

//log info
enum LOG_LEVEL { DEBUG, INFO, WARN }

class SaLogger {
  static final LOG_LEVEL logLevel = LOG_LEVEL.WARN;

  static void d(String str) {
    if (LOG_LEVEL.DEBUG.index >= logLevel.index)
      log(str, time: DateTime.now(), name: "SensorsDataAnalytics");
  }

  static void i(String str) {
    if (LOG_LEVEL.INFO.index >= logLevel.index)
      log(str, time: DateTime.now(), name: "SensorsDataAnalytics");
  }

  static void w(String str) {
    if (LOG_LEVEL.WARN.index >= logLevel.index)
      log(str, time: DateTime.now(), name: "SensorsDataAnalytics");
  }

  /// 仅仅是打印结果
  static void p(String str) {
    if (LOG_LEVEL.DEBUG.index >= logLevel.index) print(str);
  }
}

/// 用于记录路由状态，例如调用 popUntil 方法，就是表示
enum RouteStatus {
  pop_until,
  pop,
  push,
  pop_and_push,
  push_and_remove_until,
  push_replacement,
  none
}

///用来记录最后一个路由的状态，记录中间路由状态
class LastRoute {
  Route? route;
  Route? previousRoute;
  RouteStatus routeStatus = RouteStatus.none;
}
