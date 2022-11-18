import 'dart:convert' as convert;
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:sa_aspectd_impl/common/sensorsdata_logger.dart';
import 'package:sa_aspectd_impl/viewscreen/sensorsdata_viewscreen.dart';
import 'package:sa_aspectd_impl/viewscreen/sensorsdata_viewscreen_route.dart';
import 'package:sa_aspectd_impl/visualized/sensorsdata_visualized.dart';
import 'package:sa_aspectd_impl/visualized/sensorsdata_visualized_channel.dart';

import 'sensorsdata_common.dart';
import 'sensorsdata_element_resolver.dart';

///用于管理页面中的元素信息
///这些信息可用于全埋点和可视化使用
class PageInfoManager {
  //获取、更新、转换元素内容、获取元素路径、获取指定的元素等操作

  static final _instance = PageInfoManager._();

  PageInfoManager._();

  factory PageInfoManager.getInstance() => _instance;

  var projectElementNodeList = <ElementNode>[];

  ///更新整个页面元素信息
  void updateWholePageInfo() {
    //每次更新前，尝试清除已有数据
    clearAll();
    var startTime = DateTime.now().millisecondsSinceEpoch;
    SaLogger.d("开始计算页面中的元素信息");
    try {
      BuildContext? context = RouteViewScreenResolver.getInstance().lastViewScreenContext;
      if (context != null) {
        PageElementResolver pageResolver = PageElementResolver();
        pageResolver.resolver(context);
        projectElementNodeList = pageResolver.result;
      }
    } catch (e, s) {
      SaLogger.e("Can not update page data: ", error: e, stackTrace: s);
    }
    var endTime = DateTime.now().millisecondsSinceEpoch;
    SaLogger.d("计算页面信息耗时：${endTime - startTime}");
  }

  void updatePartNode(Element parentElement) {}

  ///当关闭可视化全埋点的时候，就清楚内存中的所有数据
  void clearAll() {
    projectElementNodeList.clear();
  }

  ///根据元素，获取其对应的路径，用在全埋点中。
  ///有可能获取失败，此时就需要采用常规方式来获取路径
  ElementNode? findNodeByElement(Element element) {
    return projectElementNodeList.firstWhereOrNull((node) => node.element == element);
  }

  ///根据 Node 计算路径信息
  String getPathFromNode(ElementNode node) {
    if (node.path != null) {
      return node.path!;
    }
    List<String> result = [];
    ElementNode? prevNode;
    ElementNode? currentNode = node;
    bool isDashSet = false;
    do {
      Element element = currentNode!.element;
      print(element.runtimeType.toString());
      if (!isDashSet && prevNode != null && (element.widget is ListView || element.widget is GridView)) {
        result.removeAt(0);
        result.insertAtFirst("${SAUtils.runtimeStr(prevNode.element)}[-]");
        isDashSet = true;
      }
      result.insertAtFirst("${SAUtils.runtimeStr(currentNode.element)}[${currentNode.slot}]");
      prevNode = currentNode;
    } while ((currentNode = currentNode.parentNode) != null);
    node.path = result.join("/");
    return node.path!;
  }

  ///获取对应页面中的元素信息
  ///并且将信息发送到 channel 中
  void formatPageElementInfoAndSend() {
    try {
      var startTime = DateTime.now().millisecondsSinceEpoch;
      SaLogger.d("开始拼装可视化 JSON 信息");
      VisualizedElementType visualizedElementInfo = VisualizedElementType();
      _updateElementContent();
      projectElementNodeList.forEach((node) {
        try {
          if (node.path == null || node.path!.isEmpty) {
            return;
          }
          if (_isElementShouldSend(node)) {
            VisualizedItemInfo itemInfo = VisualizedItemInfo();
            if (_calElementOtherInfo(node.element, node, itemInfo)) {
              _updatePathAndSubElements(node, itemInfo);
              visualizedElementInfo.data.add(itemInfo);
            }
          }
        } catch (e) {
          SaLogger.d("无法成功转换 element");
        }
      });
      var endTime = DateTime.now().millisecondsSinceEpoch;
      sendVisualizedData(visualizedElementInfo);

      SaLogger.d("结束拼装可视化 JSON 信息：${endTime - startTime}");
    } catch (e, s) {
      SaLogger.e("SensorsAnalytics Exception Report", stackTrace: s, error: e);
    }
  }

  void sendVisualizedData(VisualizedElementType info) {
    try {
      String result = convert.jsonEncode(info);
      SensorsAnalyticsVisualized.sendVisualizedMessage(result);
      sendVisualizedPageViewData();
    } catch (e, s) {
      SaLogger.e("SensorsAnalytics Exception Report", stackTrace: s, error: e);
    }
  }

  ///单独发送页面浏览信息
  void sendVisualizedPageViewData() {
    if (!SensorsAnalyticsVisualized.isVisualizedConnected) {
      return;
    }
    VisualizedScreenType screenType = VisualizedScreenType();
    screenType.screenInfo = ViewScreenFactory.getInstance().lastViewScreen;
    String result = convert.jsonEncode(screenType);
    SensorsAnalyticsVisualized.sendVisualizedMessage(result);
  }

  ///因为元素路径中包含可能包含 SliverList，需要将路径做修正
  void _updatePathAndSubElements(ElementNode node, VisualizedItemInfo itemInfo) {
    //如果当前 node 是 SliverList 的直接子元素
    //此时增加 sub elements 参数
    if (node.element.widget is KeyedSubtree && node.elementPosition != null) {
      var ids = <String>[];
      node.subNodeList?.forEach((subNode) {
        _setAllSubNodeIds(subNode, ids);
      });
      itemInfo.subElements = ids;
      itemInfo.isListView = true;
    }
  }

  ///收集所有的子元素信息
  void _setAllSubNodeIds(ElementNode node, List<String> idList) {
    idList.add(node.id!);
    //当遍历到下一个 ListView 的时候就停止
    if (node.element.widget is KeyedSubtree && node.parentNode != null && SAUtils.isListOrGrid(node.parentNode!.element)) {
      return;
    }
    if (node.subNodeList != null) {
      node.subNodeList!.forEach((element) {
        _setAllSubNodeIds(element, idList);
      });
    }
  }

  ///计算元素的基本信息，然后设置给 itemInfo 中
  bool _calElementOtherInfo(Element element, ElementNode node, VisualizedItemInfo itemInfo) {
    //计算大小和位置
    RenderObject? renderObj = element.findRenderObject();
    RenderBox renderBox = renderObj as RenderBox;
    Size rbSize = renderBox.size;
    itemInfo.width = rbSize.width;
    itemInfo.height = rbSize.height;
    Offset offset = renderBox.localToGlobal(Offset.zero);
    if (offset.dx.isNaN || offset.dy.isNaN) {
      return false;
    }
    itemInfo.left = offset.dx;
    itemInfo.top = offset.dy;
    itemInfo.id = node.id;

    //计算路径、位置、内容以及是否可点击
    itemInfo.elementPath = node.path;
    itemInfo.elementPosition = node.elementPosition;
    //String? elementContent = SAUtils.resolvingWidgetContent(element, searchGestureDetector: false);
    itemInfo.elementContent = node.content;
    itemInfo.level = node.level;
    if (element.widget is GestureDetector) {
      itemInfo.clickable = _isIOSTopStatusBarGestureDetector(node, itemInfo);
    }

    //设置页面信息
    var screenInfo = ViewScreenFactory.getInstance().lastViewScreen;
    itemInfo.title = screenInfo?.finalTitle;
    itemInfo.screenName = screenInfo?.finalScreenName;

    return true;
  }

  ///目前以深度优先的方式遍历树，如果从根节点向下遍历树，为了获取内容，
  ///需要获取对应节点下面的所有文本内容，这样就会遍历同一个节点多次的情况，
  ///这显然效率不高。为了解决这个问题，最好是由子节点组织好内容，父节点负责将
  ///这些内容拼装组织起来，从而减少多次遍历产生的性能问题。
  void _updateElementContent() {
    //按照深度优先的遍历方式，叶子节点会存在于列表的尾部，所以这里先遍历叶子节点
    projectElementNodeList.forEachReversed((node) {
      //或者添加 try-catch 用来获取 widget，查看其值是否可能为空
      if (_isDefunctElement(node.element)) {
        return;
      }
      //当时叶子节点时，计算其内容
      if (node.subNodeList == null || node.subNodeList!.isEmpty) {
        String? elementContent = SAUtils.resolvingWidgetContent(node.element, searchGestureDetector: false);
        node.content = elementContent;
      }
      //当不是叶子节点时，就将叶子节点中的内容组合起来作为其元素内容
      else {
        var strList = <String>[];
        node.subNodeList!.forEach((subNode) {
          if (subNode.content != null && subNode.content!.isNotEmpty) {
            strList.add(subNode.content!);
          }
        });
        node.content = strList.join("-");
      }
    });
  }

  ///判断 Element 是否可用，主要是判断
  bool _isDefunctElement(Element element) {
    //通过 try-catch 的方式来判断元素是否
    try {
      var widget = element.widget;
      if (widget == null) {
        return true;
      }
    } catch (e) {
      return true;
    }
    //这种方式会命中断言
    // var renderObj = element.renderObject;
    // if (renderObj == null) {
    //   return true;
    // }
    return false;
  }

  ///在 [projectElementNodeList] 中只有项目创建的元素才需要被发送，
  ///其他多余的 node 可以不需要管，自定义属性也只是针对用户创建的 Widget
  bool _isElementShouldSend(ElementNode node) {
    Widget widget = node.element.widget;
    return _isOffstageElementAndShouldSend(node) &&
        (SAUtils.isProjectElement(node.element) || SAUtils.isListOrGrid(node.element) || widget is KeyedSubtree || widget is GestureDetector);
  }

  ///判断是不是 iOS 顶部的点击元素，目前没有更好的方式，只做一个特征判断。PS：这种无法触发点击事件
  bool _isIOSTopStatusBarGestureDetector(ElementNode node, VisualizedItemInfo itemInfo) {
    if ((Platform.isIOS || Platform.isMacOS) &&
        itemInfo.left == 0 &&
        itemInfo.top == 0 &&
        SAUtils.isStringEmpty(node.content) &&
        _pathWithoutSlot(node.path!).endsWith("Scaffold/CustomMultiChildLayout/LayoutId/GestureDetector")) {
      return false;
    }
    return SAUtils.isGestureDetector(node.element);
  }

  String _pathWithoutSlot(String oldStr) {
    RegExp pattern = RegExp(r"\[\d+\]");
    return oldStr.replaceAll(pattern, "");
  }

  ///判断元素是否在 Offstage 中，如果存在并判断是否应该发送。
  bool _isOffstageElementAndShouldSend(ElementNode node) {
    if (node.dataNeedForChild != null && node.dataNeedForChild is Element) {
      Element element = node.dataNeedForChild;
      if (element.widget is Offstage) {
        Offstage offstage = element.widget as Offstage;
        return !offstage.offstage;
      }
    }
    return true;
  }

  ///根据元素路径从页面 Node 中寻找相匹配的元素
  Element? findElementByPath(String elementPath, String? elementPosition) {
    Element? target;
    projectElementNodeList.forEachWithReturnWork((node) {
      if (node.path == null || node.path!.isEmpty) {
        return false;
      }
      if (node.path!.length != elementPath.length) {
        return false;
      }
      if (elementPosition != null && elementPosition.isNotEmpty && "${node.elementPosition}" != elementPosition) {
        return false;
      }
      if (elementPath == node.path) {
        target = node.element;
        return true;
      }
      return false;
    });
    return target;
  }
}
