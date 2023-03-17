import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:sa_aspectd_impl/common/sensorsdata_logger.dart';

import '../sa_autotrack.dart' show isProjectCreatedElement;

@pragma("vm:entry-point")
class SAUtils {
  static const String FLUTTER_AUTOTRACK_VERSION = "2.1.1";
  static final _deviceInfoMap = <String, Object>{};
  static bool hasAddedFlutterPluginVersion = false;

  SAUtils._();

  static get baseDeviceInfo {
    if (_deviceInfoMap.isEmpty) {
      _deviceInfoMap["os"] = Platform.operatingSystem;
      _deviceInfoMap["os_version"] = Platform.operatingSystemVersion;
      _deviceInfoMap["flutter_version"] = Platform.version;
    }
    return _deviceInfoMap;
  }

  /// Resolving element content by the given element.
  static String? resolvingWidgetContent(Element element, {bool searchGestureDetector = true}) {
    var contentOjb = ElementContentResolver(element)..resolving(searchGestureDetector: searchGestureDetector);
    return contentOjb.result;
  }

  /// Calculate Widget runtime type string path from the given Element list.
  static String calElementWidgetPath(List<Element> elementList) {
    var listResult = <String>[];
    elementList.forEach((element) {
      var result = "${element.widget.runtimeType.toString()}";
      int slot = 0;
      if (element.slot != null) {
        if (element.slot is IndexedSlot) {
          slot = (element.slot as IndexedSlot).index;
        }
      }
      result += "[$slot]";
      listResult.add(result);
    });

    String finalResult = "";
    listResult.forEach((element) {
      finalResult += "/$element";
    });

    if (finalResult.startsWith('/')) {
      finalResult = finalResult.replaceFirst('/', '');
    }
    return finalResult;
  }

  ///Try to get text string from Widget
  static String? try2GetText(Widget widget) {
    String? result;
    if (widget is Text) {
      result = widget.data;
    } else if (widget is RichText) {
      //针对 RichText 进行处理，因为 Icon 这个 Widget 使用的是 RichText 来实现的。
      RichText tmp = widget;
      if (tmp.text is TextSpan) {
        TextSpan textSpan = tmp.text as TextSpan;
        try {
          String? fontFamily = textSpan.style?.fontFamily;
          //对于系统提供的 Icon，其 family 都是统一的 MaterialIcons，当出现这种情况的时候就认为没有采集到文字信息，采集平级或者向上去找文字信息
          if (fontFamily != "MaterialIcons") {
            result = textSpan.toPlainText(includePlaceholders: false, includeSemanticsLabels: false);
          }
        } catch (e) {
          result = textSpan.toPlainText(includePlaceholders: false, includeSemanticsLabels: false);
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

  static void setupLibPluginVersion(Map<String, dynamic>? map) {
    if (!hasAddedFlutterPluginVersion && map != null) {
      map[r"$lib_plugin_version"] = ["flutter:$FLUTTER_AUTOTRACK_VERSION"];
      hasAddedFlutterPluginVersion = true;
    }
  }

  /// Search down to find all GestureDetector and project created Elements follow the [topElement]
  static List<Element> searchAllProjectElements(Element topElement) {
    ElementSearcher elementSearcher = ElementSearcher(topElement, (element) {
      return SAUtils.isGestureDetector(element) || isProjectCreatedElement(element);
    })
      ..resolving();
    return elementSearcher.result;
  }

  /// Get element slot value
  static int getSlotValue(Element element) {
    dynamic slot = element.slot;
    int slotValue;
    if (slot != null) {
      if (slot is IndexedSlot) {
        slotValue = slot.index;
      } else if (slot is int) {
        slotValue = slot;
      } else if (slot.runtimeType.toString().startsWith("_ListTileSlot")) {
        slotValue = slot.index;
      } else if (slot.runtimeType.toString().startsWith("_TableSlot")) {
        //这里是假定列不超过 1000，行不超过 10000，然后组合一个不重复的数字
        int column = slot.column;
        column = (1000 + column) * 100000; //1001 00000
        int row = slot.row;
        row = 10000 + row;
        slotValue = column + row;
      } else {
        slotValue = 0;
      }
    } else {
      slotValue = 0;
    }
    return slotValue;
  }

  static String runtimeStr(Element element) => "${element.widget.runtimeType.toString()}";

  static bool isStringEmpty(String? str) => str == null || str.isEmpty;

  static bool isStringNotEmpty(String? str) => str != null && str.isNotEmpty;

  ///检查元素是否应该添加到路径中。
  ///包括检测是否是项目文件、是否是可点击的 GestureDetector、是否有多个子节点等
  static bool checkElementForPath(Element element) {
    return isProjectCreatedElement(element) || isGestureDetector(element) || isElementHasChildren(element);
  }

  ///判断 Element 是否存可能存在多个元素
  static bool isElementHasChildren(Element element) {
    return element is SliverMultiBoxAdaptorElement ||
        element is MultiChildRenderObjectElement ||
        element is ListWheelElement ||
        element.widget is Table;
  }

  ///判断是否是 GestureDetector
  static bool isGestureDetector(Element element) {
    Widget widget = element.widget;
    return widget is GestureDetector &&
        widget.onTap != null &&
        widget.onLongPress == null &&
        widget.onDoubleTap == null;
  }

  ///判断是否项目中元素
  static bool isProjectElement(Element element) => isProjectCreatedElement(element);

  ///判断是否是 List 或 Grid
  static bool isListOrGrid(Element element) => element.widget is SliverList || element.widget is SliverGrid;
}

///Helper class to resolving element content.
///This resolver will search up a GestureDetector element,
///then get texts below it.
@pragma("vm:entry-point")
class ElementContentResolver {
  final Element _element;
  Element? _gestureElement;
  final List<String> _contentList = [];

  ElementContentResolver(this._element);

  String? get result => _contentList.isEmpty ? null : _contentList.join("-");

  void resolving({bool searchGestureDetector = true}) {
    if (searchGestureDetector) {
      _searchGestureDetectorElement(_element);
    } else {
      _gestureElement = _element;
    }
    _elementVisitor(_gestureElement);
  }

  void _elementVisitor(Element? element) {
    try {
      if (element != null) {
        String? tmp = SAUtils.try2GetText(element.widget);
        if (tmp != null && tmp.isNotEmpty) {
          _contentList.add(tmp);
          return;
        }
        element.visitChildElements(_elementVisitor);
      }
    } catch (e) {
      SaLogger.e("fail to get element content", error: e);
    }
  }

  void _searchGestureDetectorElement(Element element) {
    if (SAUtils.isGestureDetector(element)) {
      _gestureElement = element;
      return;
    }
    element.visitAncestorElements((element) {
      if (SAUtils.isGestureDetector(element)) {
        _gestureElement = element;
        return false;
      }
      return true;
    });
  }
}

/// Search down to find specified elements
@pragma("vm:entry-point")
class ElementSearcher {
  final Element _element;
  final ElementChecker _checker;
  final _resultList = <Element>[];

  ElementSearcher(this._element, this._checker);

  List<Element> get result => _resultList;

  void resolving() {
    _tryChecker(_element);
    _element.visitChildElements(_elementVisitor);
  }

  void _elementVisitor(Element element) {
    _tryChecker(element);
    element.visitChildElements(_elementVisitor);
  }

  void _tryChecker(Element element) {
    if (_checker(element)) {
      _resultList.add(element);
    }
  }
}

typedef ElementChecker = bool Function(Element element);

extension IteratorExt<E> on Iterable<E> {
  E? firstWhereOrNull(bool test(E element)) {
    for (E element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

extension ListExt<E> on List<E> {
  void insertAtFirst(E element) {
    //TODO 后面可以看看这种操作的效率
    this.insert(0, element);
  }

  ///方向遍历列表
  void forEachReversed(void f(E element)) {
    if (this.isEmpty) {
      return;
    }
    for (int index = length - 1; index >= 0; index--) {
      f(this[index]);
    }
  }

  ///让 forEach 根据返回值来决定是否整体退出
  ///当为 true 的时候，就直接退出所有
  void forEachWithReturnWork(bool f(E element)) {
    for (E e in this) {
      if (f(e)) return;
    }
  }
}

void tryCatchLambda(void f()) {
  try {
    f();
  } catch (e, s) {
    SaLogger.e("SensorsAnalytics Exception Report: ", stackTrace: s, error: e);
  }
}
