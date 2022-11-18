import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:sa_aspectd_impl/common/sensorsdata_common.dart';

import 'sensorsdata_logger.dart';

///作用：用于计算页面元素信息的文件
class PageElementResolver {
  var projectElementNodeList = <ElementNode>[];
  Random _random = Random();
  int elementLevel = 0;

  PageElementResolver();

  void resolver(BuildContext context) {
    try {
      elementLevel = 0;
      Element element = context as Element;
      var node = ElementNode(element);
      //因为传递过来的 context 可能并不是项目中的，所以判断一下
      //如果不是的话，就将其 path 设置为空，这样也不影响最终的结果
      if (!SAUtils.isProjectElement(element)) {
        node.path = "";
      } else {
        _setNodePath(node);
      }
      projectElementNodeList.add(node);
      element.visitChildElements((element) {
        _visitChild(element, node);
      });
    } catch (e, s) {
      SaLogger.e("SensorsAnalytics Exception Report", stackTrace: s, error: e);
    }
  }

  void _visitChild(Element element, ElementNode parentNode, {int level = 1}) {
    //对特定的元素做特殊处理，如果是特殊元素就不对起采集元素信息
    if (_specialWidgetTest(element, parentNode)) {
      return;
    }
    elementLevel++;

    //判断是否是项目所建元素，或者是否是 GestureDetector
    if (_shouldAddToNode(element, parentNode)) {
      level++;
      //1.设置当前节点信息
      ElementNode vNode = ElementNode(element);
      if (element.widget is Offstage) {
        vNode.dataNeedForChild = element;
      } else {
        vNode.dataNeedForChild = parentNode.dataNeedForChild;
      }
      //当前节点所在的位置由父节点计算得出
      if (parentNode.subNodeList == null) {
        parentNode.subNodeList = [];
        vNode.position = 0;
      } else {
        vNode.position = (parentNode.subNodeList!.length) + 1;
      }
      vNode.level = elementLevel;
      vNode.parentNode = parentNode;
      vNode.slot = SAUtils.getSlotValue(element);
      _setNodePath(vNode);
      projectElementNodeList.add(vNode);
      if (SAUtils.isElementHasChildren(element)) {
        vNode._childrenAlsoAdd = true;
      }

      //2.对父节点进行操作
      parentNode.subNodeList!.add(vNode);
      //将当前节点赋值给父节点，用于下一次遍历
      parentNode = vNode;
    }

    element.visitChildElements((element) {
      _visitChild(element, parentNode, level: level);
    });
  }

  ///判断元素是否是特殊类型，如果是特殊类型，并且不希望再遍历子元素就返回 true
  bool _specialWidgetTest(Element element, ElementNode? parentNode) {
    //因为 ExpansionPanelList 路径存在变动的情况，目前可视化全埋点不对其支持，
    //忽略其后的所有元素信息，后面有方案再做处理
    if (element.widget is ExpansionPanelList) {
      return true;
    }
    //针对 Indexed Stack，防止获得 Stack 中所有的结果，根据 indexed 选择需要获取的 Element
    if (parentNode != null && parentNode.element.widget is IndexedStack) {
      IndexedStack stack = parentNode.element.widget as IndexedStack;
      if (stack.index != SAUtils.getSlotValue(element)) {
        return true;
      }
    }
    return false;
  }

  ///设置 Node 的 Path 信息
  void _setNodePath(ElementNode node) {
    String result;
    //当列表嵌套列表时，需要更新原路径中的 [-]
    bool _resetParentPath = false;
    //如果是 SliverList 中的第一个子元素，路径中就设置[-]
    if (node.element.widget is KeyedSubtree && node.parentNode != null && SAUtils.isListOrGrid(node.parentNode!.element)) {
      result = "${SAUtils.runtimeStr(node.element)}[-]";
      node.elementPosition = node.slot;
      _resetParentPath = true;
    } else {
      result = "${SAUtils.runtimeStr(node.element)}[${node.slot}]";
      //子元素继承自父节点的元素位置，适用于列表元素
      if (node.parentNode != null) {
        node.elementPosition = node.parentNode!.elementPosition;
      }
    }
    if (node.parentNode != null && node.parentNode!.path != null && node.parentNode!.path!.isNotEmpty) {
      String parentPath = node.parentNode!.path!;
      if (_resetParentPath && parentPath.contains("-")) {
        parentPath = parentPath.replaceAll("-", node.parentNode!.elementPosition!.toString());
      }
      result = "$parentPath/$result";
    }
    node.path = result;
    node.id = _random.nextInt(10000000).toString() + "${node.elementPosition ?? node.slot}".toString();
  }

  ///判断 Element 是不是特定的元素，如果是就添加为 Node
  bool _shouldAddToNode(Element element, ElementNode parentNode) {
    if (SAUtils.checkElementForPath(element)) {
      return true;
    } else if (parentNode._childrenAlsoAdd) {
      return true;
    }
    return false;
  }

  List<ElementNode> get result {
    //_removeUnusedNode();
    return projectElementNodeList;
  }

  ///按照现在的计算规则，特别是满足 [_isElementHasChildren]
  void _removeUnusedNode() {
    var noneProjectNodeList = <ElementNode>[];
    projectElementNodeList.forEach((node) {
      //找到非项目对应的子节点
      if ((node.subNodeList == null || node.subNodeList!.isEmpty) && !SAUtils.isProjectElement(node.element)) {
        noneProjectNodeList.add(node);
      }
    });

    noneProjectNodeList.forEach((node) {
      projectElementNodeList.remove(node);
      if (node.parentNode != null) {
        node.parentNode?.subNodeList?.remove(node);
        if (node.parentNode!.subNodeList!.isEmpty) {
          projectElementNodeList.remove(node.parentNode);
        }
      }
    });
  }
}

///页面元素 Node, 用于存放最基本的内容
class ElementNode {
  final Element element;
  String? path;
  String? content;
  String? id;

  ///当前节点的深度
  int level = -1;

  ///位于父节点中的位置，参考 Flutter Inspector 中的视图位置
  int position = -1;

  ///正常父节点提供的值
  int slot = 0;

  ///位于列表中的元素才会有该值，如果父节点中有该值，子元素需要都继承该值
  int? elementPosition;

  ///对于符合 [_isElementHasChildren] 的 Element，它的直接子元素也应该添加到路径中
  bool _childrenAlsoAdd = false;

  ///有些数据需要子元素也知道，为了减少向上查找带来的性能消耗，将这些信息封装在此，
  ///方便做业务逻辑判断。比如 Offstage，需要子元素知道 Offstage 的显示状态，
  ///从而确定子元素是否应该将其信息发送给服务端。
  dynamic dataNeedForChild;

  ///子节点，例如用于父节点获取子节点中的内容
  List<ElementNode>? subNodeList;
  ElementNode? parentNode;

  ElementNode(this.element);
}
