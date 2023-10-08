import 'package:flutter/material.dart';
import 'package:sa_aspectd_impl/viewscreen/sensorsdata_viewscreen_route.dart';
import 'sensorsdata_common.dart';
import 'sensorsdata_logger.dart';

///用于获取全埋点元素点击时的路径，注意这与可视化状态下获取的路径需要保持一致
class PathResolver {
  List<String> path = [];
  List<Element> elementList = [];
  Element? prevElement;
  int? _elementPosition;
  ElementChecker? _checker;
  bool _isFoundExpansionPanelList = false;

  ///if current path contains Offstage/Visibility widget, and it's offstage field is true, we should ignore this Element
  bool _shouldIgnore = false;

  ///check current element is contained in SliverList or SliverGrid
  Element? _sliverListElement;

  PathResolver(this._checker);

  void resolve(Element element) {
    try {
      element = _findSpecificElement(element) ?? element;
      path.add("${SAUtils.runtimeStr(element)}[${SAUtils.getSlotValue(element)}]");
      elementList.add(element);
      element.visitAncestorElements((element) {
        //当遍历到当前页面浏览对应的 Context 时就退出
        if (element == RouteViewScreenResolver.getInstance().lastViewScreenContext) {
          return false;
        }
        if(!element.mounted){
          return false;
        }
        //可视化不支持类似操作
        if (element.widget is ExpansionPanelList) {
          _isFoundExpansionPanelList = true;
        }
        //KeyedSubtree
        if (SAUtils.isListOrGrid(element) && prevElement != null && prevElement!.widget is KeyedSubtree) {
          _sliverListElement = prevElement;
        }
        if (element.widget is Offstage) {
          Offstage offstage = element.widget as Offstage;
          _shouldIgnore = offstage.offstage;
        }
        if (element.widget.runtimeType.toString() == "Visibility") {
          dynamic visibility = element.widget;
          _shouldIgnore = visibility.visible;
        }
        int slotValue = SAUtils.getSlotValue(element);
        //1. if element has multi children
        if (SAUtils.isElementHasChildren(element)) {
          if (prevElement != null) {
            //if previous element is valid, means that the previous element is already added to path, so needs remove and re-add it.
            if (SAUtils.checkElementForPath(prevElement!)) {
              if (path.isNotEmpty) {
                path.removeAt(0);
                elementList.removeAt(0);
              }
            }
            //only SliverList and SliverGrid calculate element position
            //对于 List 和 Grid，路径中需要添加 [-] 以及计算 position
            //_elementPosition 的作用是保证路径中只会计算一次，特别是对嵌套列表的情况
            if (_elementPosition == null && SAUtils.isListOrGrid(element)) {
              path.insertAtFirst("${SAUtils.runtimeStr(prevElement!)}[${_elementPosition == null ? "-" : SAUtils.getSlotValue(prevElement!)}]");
              elementList.insertAtFirst(prevElement!);
              if (_elementPosition == null) _elementPosition = SAUtils.getSlotValue(prevElement!);
            } else {
              path.insertAtFirst("${SAUtils.runtimeStr(prevElement!)}[${SAUtils.getSlotValue(prevElement!)}]");
              elementList.insertAtFirst(prevElement!);
            }
          }
          //add the current element
          path.insertAtFirst("${SAUtils.runtimeStr(element)}[$slotValue]");
          elementList.insertAtFirst(element);
          prevElement = element;
          return true;
        }

        //2. if local widget or special widget, add it
        if (SAUtils.checkElementForPath(element)) {
          path.insertAtFirst("${SAUtils.runtimeStr(element)}[$slotValue]");
          elementList.insertAtFirst(element);
          prevElement = element;
          return true;
        }
        prevElement = element;
        return true;
      });
    } catch (e, s) {
      SaLogger.e("SensorsAnalytics Exception Report", stackTrace: s, error: e);
    }
  }

  PathEntry get result => PathEntry(path.join("/"), elementPosition, elementList)
    ..hasFoundExpansionPanelList = _isFoundExpansionPanelList
    ..shouldIgnore = _shouldIgnore
    ..sliverListElement = _sliverListElement;

  /// Get element position if the element path contains SliverList or SliverGrid
  int? get elementPosition => _elementPosition;

  ///eg, for click, we should first find clickable GestureDetector,
  Element? _findSpecificElement(Element element) {
    if (_checker == null) {
      return null;
    }
    if (_checker!(element)) {
      return element;
    }
    Element? finalResult;
    element.visitAncestorElements((element) {
      if (_checker!(element)) {
        finalResult = element;
        return false;
      }
      return true;
    });
    return finalResult;
  }
}

///用于封装路径的基本信息
class PathEntry {
  String path;
  List<Element> elementList;
  final int? elementPosition;
  bool hasFoundExpansionPanelList = false;

  //not used
  bool shouldIgnore = false;

  //not used
  Element? sliverListElement;

  PathEntry(this.path, this.elementPosition, this.elementList);
}
