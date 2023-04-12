import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:sa_aspectd_impl/common/sensorsdata_element_resolver.dart';
import 'package:sa_aspectd_impl/common/sensorsdata_page_info.dart';
import 'package:sa_aspectd_impl/common/sensorsdata_path_resolver.dart';
import 'package:sa_aspectd_impl/viewscreen/sensorsdata_viewscreen.dart';
import 'package:sensors_analytics_flutter_plugin/sensors_analytics_flutter_plugin.dart';

import '../common/sensorsdata_common.dart';
import '../common/sensorsdata_logger.dart';
import '../config/sensorsdata_autotrack_config.dart';
import '../visualized/sensorsdata_visualized_properties.dart';

@pragma("vm:entry-point")
class AppClickResolver {
  var _curPointerCode = -1;
  var _prePointerCode = -1;
  var clickRenderMap = <int, RenderObject>{}; //基于此可以获得路径信息
  var currentEvent;
  late HitTestEntry hitTestEntry;
  var elementInfoMap = <String, dynamic>{};
  String? contentText;
  bool searchStop = false;

  ///用于拼装 element content
  List<String> contentList = [];

  ///element type 对应的 widget
  var elementTypeWidget;

  ///用于适配 ExpansionPanelList 的点击事件
  bool _expansionPanelListHeaderPressed = false;
  int _expansionPanelListerHeaderPressedIndex = -1;

  static final _instance = AppClickResolver._();

  AppClickResolver._();

  factory AppClickResolver.getInstance() => _instance;

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

  void trackClick(String? eventName) async{
    if (eventName == "onTap") {
      contentText = null;
      searchStop = false;
      elementInfoMap.clear();
      elementTypeWidget = null;
      try {
        //添加 $AppClick 忽略
        if(await SensorsAnalyticsAutoTrackConfig.getInstance().isAutoTrackClickIgnored()){
          return;
        }

        RenderObject renderObject = hitTestEntry.target as RenderObject;
        DebugCreator debugCreator = renderObject.debugCreator as DebugCreator;
        //TODO 此处可能返回的值为空，具体什么时候为空，目前还未复现出来，后面需要额外关注
        //JIRA: https://jira.sensorsdata.cn/browse/SDK-3556
        //先向上找到 GestureDetector
        Element? newElement = findGestureDetectorElement(debugCreator.element, (e) {
          if (SAUtils.isGestureDetector(e)) {
            return true;
          }
          return false;
        });
        if (newElement == null) {
          return null;
        }
        ElementNode? elementNode = _getElementPath(newElement);
        if (elementNode == null) {
          return;
        }
        _wrapElementContent(newElement);
        _setupClickEventScreenInfo();
        _printClick(elementInfoMap);
        elementInfoMap[r"$lib_method"] = "autoTrack";
        SAUtils.setupLibPluginVersion(elementInfoMap);
        //自定义属性相关配置
        VisualizedPropertyManager.getInstance().resolveClickProperties(properties: elementInfoMap);
        SensorsAnalyticsFlutterPlugin.track(r"$AppClick", elementInfoMap);
      } catch (e, s) {
        SaLogger.e("SensorsAnalytics Exception Report", stackTrace: s, error: e);
      } finally {
        _resetAppClick();
      }
    }
  }

  /// 用来辅助计算 ExpansionPanelList 中 Header 对应的点击事件
  void handleExpansionPanelPressed(int index) {
    _expansionPanelListHeaderPressed = true;
    _expansionPanelListerHeaderPressedIndex = index;
  }

  /// 对已经计算的路径进行检查，对其结果做修正，
  /// 典型就是修正 ExpansionPanelList 中的元素路径
  void _checkPath(PathEntry pathEntry) {
    _checkExpansionPanelPath(pathEntry);
  }

  /// 查看其是否包含有 ExpansionPanelList，
  void _checkExpansionPanelPath(PathEntry pathEntry) {
    try {
      if (!pathEntry.hasFoundExpansionPanelList) {
        return;
      }
      if (_expansionPanelListHeaderPressed) {
        var sampleList = ["ExpansionPanelList", "_MergeableMaterialListBody", "ListBody", "Container", "Column", "MergeSemantics"];
        int start = -1, end = -1, current = 0, sampleListIndex = 0;
        bool startMatch = false, isAllMatch = false;
        pathEntry.elementList.forEach((element) {
          String widgetStr = SAUtils.runtimeStr(element);

          if (startMatch && !isAllMatch) {
            if (widgetStr != sampleList[++sampleListIndex]) {
              start = -1;
              startMatch = false;
              sampleListIndex = 0;
            } else {
              if (sampleList.length == (sampleListIndex + 1)) {
                isAllMatch = true;
                end = current;
              }
            }
          }
          if (widgetStr == sampleList[0]) {
            start = current;
            startMatch = true;
            sampleListIndex = 0;
          }
          current++;
        });

        pathEntry.elementList.removeRange(start + 2, end + 1);
        var newPathStr = [];
        pathEntry.elementList.reversed.forEach((element) {
          if (SAUtils.runtimeStr(element) == "_MergeableMaterialListBody") {
            newPathStr.insert(0, "${SAUtils.runtimeStr(element)}[$_expansionPanelListerHeaderPressedIndex]");
          } else {
            newPathStr.insert(0, "${SAUtils.runtimeStr(element)}[${SAUtils.getSlotValue(element)}]");
          }
        });
        pathEntry.path = newPathStr.join("/");
      } else {
        Element element = pathEntry.elementList.lastWhere((element) => element.widget is ExpansionPanelList);
        ExpansionPanelList widget = element.widget as ExpansionPanelList;
        List<ExpansionPanel> panelList = widget.children;
        int groupPosition = panelList.indexWhere((element) {
          Widget bodyWidget = element.body;
          return pathEntry.elementList.indexWhere((element) => element.widget == bodyWidget) != -1;
        });
        //说明找到了对应组的位置
        if (groupPosition != -1) {
          Widget bodyWidget = panelList[groupPosition].body;
          var newElementList = <Element>[];
          bool startIgnore = false;
          for (int index = pathEntry.elementList.length - 1; index >= 0; index--) {
            if (pathEntry.elementList[index].widget == bodyWidget) {
              startIgnore = true;
              newElementList.add(pathEntry.elementList[index]);
            }
            if (startIgnore && SAUtils.runtimeStr(pathEntry.elementList[index]) == "_MergeableMaterialListBody") {
              startIgnore = false;
            }
            if (!startIgnore) {
              newElementList.add(pathEntry.elementList[index]);
            }
          }
          pathEntry.elementList = newElementList;
          var newPathStr = [];
          pathEntry.elementList.forEach((element) {
            if (SAUtils.runtimeStr(element) == "_MergeableMaterialListBody") {
              newPathStr.insert(0, "${SAUtils.runtimeStr(element)}[$groupPosition]");
            } else {
              newPathStr.insert(0, "${SAUtils.runtimeStr(element)}[${SAUtils.getSlotValue(element)}]");
            }
          });
          pathEntry.path = newPathStr.join("/");
        }
      }
    } catch (e) {
      SaLogger.e("SensorsData Error (_checkExpansionPanelPath)", error: e);
    }
  }

  void _resetAppClick() {
    contentText = null;
    searchStop = false;
    elementInfoMap.clear();
    elementTypeWidget = null;
    contentList.clear();
    _expansionPanelListHeaderPressed = false;
  }

  ///如果修改此方法，记得一定要修改 getElementType
  void _wrapElementContent(Element element) {
    String? elementContent = SAUtils.resolvingWidgetContent(element);
    elementInfoMap[r"$element_content"] = elementContent;
  }

  ElementNode? _getElementPath(Element element) {
    ElementNode node = _getProjectElementPath(element);
    String elementPath = PageInfoManager.getInstance().getPathFromNode(node);
    elementInfoMap[r"$element_path"] = elementPath;
    if (node.elementPosition != null) {
      elementInfoMap[r"$element_position"] = "${node.elementPosition}";
    }
    return node;
  }

  ///获取项目中创建的元素信息
  ///与[SAUtils.getProjectElementPath(element)]逻辑相同，
  ///不过这里需要对包含 ExpansionPanelList 的 path 做一些修正。
  ElementNode _getProjectElementPath(Element element) {
    ElementNode? node = PageInfoManager.getInstance().findNodeByElement(element);
    if (node != null) {
      return node;
    }
    var r = PathResolver(null)..resolve(element);
    PathEntry entry = r.result;
    _checkPath(entry);
    ElementNode resultNode = ElementNode(element);
    resultNode.path = entry.path;
    resultNode.elementPosition = entry.elementPosition;
    return resultNode;
  }

  Element? findGestureDetectorElement(Element element, ElementChecker? _checker) {
    if (_checker == null) {
      return null;
    }
    if (_checker(element)) {
      return element;
    }
    Element? finalResult;
    element.visitAncestorElements((element) {
      if (_checker(element)) {
        finalResult = element;
        return false;
      }
      return true;
    });
    return finalResult;
  }

  void _setupClickEventScreenInfo() {
    if (ViewScreenFactory.getInstance().lastViewScreen != null) {
      elementInfoMap.addAll(ViewScreenFactory.getInstance().lastViewScreen!.toSDKMap(isClick: true) as Map<String, dynamic>);
    }
  }

  void _printClick(Map<String, dynamic> otherData) {
    String result = "";
    result += "\n==========================================Clicked========================================\n";
    SAUtils.baseDeviceInfo.forEach((key, value) {
      result += "$key: $value\n";
    });
    otherData.forEach((key, value) {
      result += "$key: $value\n";
    });
    result += "time: ${DateTime.now().toString()}\n";
    result += "=========================================================================================";
    SaLogger.i(result);
  }
}
