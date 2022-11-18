import 'dart:convert' as convert;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sa_aspectd_impl/common/sensorsdata_common.dart';
import 'package:sa_aspectd_impl/common/sensorsdata_logger.dart';

import '../common/sensorsdata_page_info.dart';
import 'sensorsdata_visualized.dart';

///可视化全埋点自定义属性管理类
class VisualizedPropertyManager {
  static final _instance = VisualizedPropertyManager._();

  VisualizedPropertyManager._();

  factory VisualizedPropertyManager.getInstance() => _instance;
  VisualizedPropertyConfig? _propertyConfig;
  Map<String, List<VisualizedPropertyEvents>>? _screenEventMap;

  ///解析自定义属性，[jsonBase64Str] 是 Base64 信息
  void parseJson(String? jsonBase64Str) {
    try {
      if (jsonBase64Str == null) {
        return;
      }
      Future<_KeyValuePair<VisualizedPropertyConfig, Map<String, List<VisualizedPropertyEvents>>>> future = compute(startConvert, jsonBase64Str);
      future.then((pair) {
        _propertyConfig = pair.key;
        _screenEventMap = pair.value;
      }).whenComplete(() {});
    } catch (e, s) {
      SaLogger.e("SensorsAnalytics Exception Report", stackTrace: s, error: e);
    }
  }

  ///解析配置
  ///返回值 map 的 key 是对应的 model，value 是 screen_name 和事件配置的映射
  static Future<_KeyValuePair<VisualizedPropertyConfig, Map<String, List<VisualizedPropertyEvents>>>> startConvert(String data) async {
    try {
      //转换成 json
      var tmp = convert.base64Decode(data);
      String jsonStr = convert.Utf8Decoder().convert(tmp);
      Map<String, dynamic> jsonData = convert.jsonDecode(jsonStr);
      VisualizedPropertyConfig result = VisualizedPropertyConfig.fromJson(jsonData);
      //删除不必要的属性配置，构建根据页面名称寻找配置的 Map
      Map<String, List<VisualizedPropertyEvents>> screenAndEventsMap = {};
      result.events?.removeWhere((events) => events.properties == null || events.properties!.isEmpty);
      result.events?.forEach((events) {
        String screenName = events.eventItem!.screenName!;
        List<VisualizedPropertyEvents>? eventsList = screenAndEventsMap[screenName];
        if (eventsList == null) {
          eventsList = [];
        }
        eventsList.add(events);

        screenAndEventsMap[screenName] = eventsList;
      });
      return _KeyValuePair(result, screenAndEventsMap);
    } catch (e, s) {
      SaLogger.e("SensorsAnalytics Exception Report", stackTrace: s, error: e);
      throw e;
    }
  }

  ///根据页面名称获取页面中存在自定义属性的配置
  List<VisualizedPropertyEvents>? getEventsByScreenName(String screenName) {
    if (_screenEventMap != null) {
      return _screenEventMap![screenName];
    }
    return null;
  }

  ///判断是否存在自定义属性配置
  bool isPropertyExists() => _propertyConfig != null;

  ///判断当前页面是否存在自定义属性配置
  bool isCurrentPageHasEvents(String? screenName) => screenName != null && _screenEventMap != null && _screenEventMap![screenName] != null;

  ///当点击发生的时候，用于判断和获取当前页面的自定义属性配置
  Map<String, dynamic>? resolveClickProperties({required Map<String, dynamic>? properties}) {
    try {
      if (properties == null) {
        return properties;
      }
      String? elementPath = properties[r"$element_path"];
      String? elementContent = properties[r"$element_content"];
      String? elementPosition = properties[r"$element_position"];
      String? screenName = properties[r"$screen_name"];

      if (!isCurrentPageHasEvents(screenName)) {
        return properties;
      }
      VisualizedStatusManager.getInstance().updatePageRefresh(true);
      List<VisualizedPropertyEvents> eventsList = _screenEventMap![screenName]!;
      eventsList.forEach((events) {
        if (_hitEventConfig(events, elementPath, elementContent, elementPosition)) {
          _processHitEventConfig(events, properties, elementPath, elementContent, elementPosition);
        }
      });
    } catch (e, s) {
      SaLogger.e("SensorsAnalytics Exception Report", stackTrace: s, error: e);
    }
    return properties;
  }

  ///处理命中的事件配置
  void _processHitEventConfig(
      VisualizedPropertyEvents events, Map<String, dynamic> properties, String? elementPath, String? elementContent, String? elementPosition) {
    VisualizedPropertyEventItem eventItem = events.eventItem!;
    events.properties!.forEach((property) {
      if (property.regular == null) {
        return;
      }
      try {
        RegExp regExp = RegExp(property.regular!);
        String? newPosition;
        if (!eventItem.limitElementPosition) {
          newPosition = elementPosition;
        } else {
          newPosition = property.elementPosition;
        }

        Element? element;
        //如果 eventItem 是不限定元素，还需要判断当前自定义属性的元素是否在列表中
        if (SAUtils.isStringNotEmpty(eventItem.elementPosition) && !eventItem.limitElementPosition) {
          //如果 property elementPosition 不为空，说明 property 也是在列表中，这就相当于内嵌列表的场景
          String? listPathPrefix = _getListPathSlice(eventItem.elementPath!);
          if (listPathPrefix == null) {
            return;
          }
          //判断 Property 是否在列表内部
          String? propertyRealPath = _getPropertyPathInInnerList(property, eventItem, listPathPrefix, newPosition!);
          if (propertyRealPath != null) {
            element = PageInfoManager.getInstance().findElementByPath(propertyRealPath, property.elementPosition);
          }
        }
        if (element == null) element = PageInfoManager.getInstance().findElementByPath(property.elementPath!, newPosition);
        if (element == null) return;
        String? content = SAUtils.resolvingWidgetContent(element, searchGestureDetector: false);
        if (content != null && content.isNotEmpty) {
          String? result = regExp.stringMatch(content);
          String eventType = property.type!;
          switch (eventType) {
            case "STRING":
              if (result != null && result.isNotEmpty) {
                properties[property.name!] = result;
              }
              break;
            case "NUMBER":
              if (result != null && result.isNotEmpty) {
                try {
                  var castData = num.parse(result);
                  properties[property.name!] = castData;
                } catch (e) {
                  SaLogger.e("cast string to num error, string is: $result", error: e);
                }
              }
              break;
          }
        }
      } catch (e, s) {
        SaLogger.e("the regular is illegal. It's value is ${property.regular}", stackTrace: s, error: e);
        return;
      }
    });
  }

  ///判断自定义属性是否在内部列表中，如果在话就会返回处理后的元素路径。处理后的元素路径会被修正为所在点击位置的路径，否则返回 null
  String? _getPropertyPathInInnerList(
      VisualizedPropertyEventProperty property, VisualizedPropertyEventItem eventItem, String listPathPrefix, String newPosition) {
    //如果 Property 没有位置信息，说明其不在列表中，直接返回
    if (SAUtils.isStringEmpty(property.elementPosition)) {
      return null;
    }

    String elementPath = property.elementPath!;
    //假设属性在内嵌列表中，那么它的路径应该满足下判断
    String pathPrefix = "${listPathPrefix}KeyedSubtree[${eventItem.elementPosition!}]";
    if (elementPath.startsWith(pathPrefix)) {
      //如果在列表中就替换为点击所在位置的路径
      return elementPath.replaceAll(pathPrefix, "${listPathPrefix}KeyedSubtree[$newPosition]");
    }
    return null;
  }

  ///获取元素列表中的片段，用于属性路径校验
  String? _getListPathSlice(String eventItemElementPath) {
    int index = eventItemElementPath.lastIndexOf("KeyedSubtree[-]");
    if (index == -1) {
      return null;
    }
    return eventItemElementPath.substring(0, index);
  }

  ///判断是否命中事件配置，true 表示命中事件配置
  bool _hitEventConfig(VisualizedPropertyEvents events, String? elementPath, String? elementContent, String? elementPosition) {
    if (elementPath == null || events.eventItem == null) {
      return false;
    }
    //1.校验 element path
    if (events.eventItem!.elementPath != elementPath) {
      return false;
    }
    //2.校验元素内容
    if (events.eventItem!.limitElementContent && elementContent != events.eventItem!.elementContent) {
      return false;
    }
    //3.校验元素位置
    if (events.eventItem!.limitElementPosition && elementPosition != events.eventItem!.elementPosition) {
      return false;
    }
    //4.校验属性配置是否为空
    if (events.properties == null || events.properties!.isEmpty) {
      return false;
    }
    return true;
  }
}

///键值对
class _KeyValuePair<K, V> {
  K key;
  V value;

  _KeyValuePair(this.key, this.value);
}

///可视化全埋点自定义属性配置
class VisualizedPropertyConfig {
  String? version;
  String? project;
  String? appId;
  String? os;
  List<VisualizedPropertyEvents>? events = [];

  VisualizedPropertyConfig.fromJson(Map<String, dynamic> json)
      : version = json['version'],
        project = json['project'],
        appId = json['app_id'],
        os = json['os'],
        events = List<VisualizedPropertyEvents>.from(json["events"].map((x) => VisualizedPropertyEvents.fromJson(x)));
}

///可视化全埋点自定义属性中的事件
class VisualizedPropertyEvents {
  String? eventName;
  String? eventType;
  VisualizedPropertyEventItem? eventItem;
  List<VisualizedPropertyEventProperty>? properties = [];

  VisualizedPropertyEvents.fromJson(Map<String, dynamic> json)
      : eventName = json['event_name'],
        eventType = json['event_type'],
        eventItem = VisualizedPropertyEventItem.fromJson(json['event']),
        properties = List<VisualizedPropertyEventProperty>.from(json["properties"].map((x) => VisualizedPropertyEventProperty.fromJson(x)));
}

///自定义属性对应的事件校验信息
class VisualizedPropertyEventItem {
  String? elementPath;
  String? elementPosition;
  String? elementContent;
  String? screenName;
  bool limitElementPosition = false;
  bool limitElementContent = false;

  //下面三个是 H5 需要的值，Flutter 不需要处理
  String? urlHost;
  String? urlPath;
  bool h5 = false;

  VisualizedPropertyEventItem.fromJson(Map<String, dynamic> json)
      : elementPath = json['element_path'],
        elementPosition = json['element_position'],
        elementContent = json['element_content'],
        screenName = json['screen_name'],
        limitElementPosition = json['limit_element_position'],
        limitElementContent = json['limit_element_content'];
}

///自定义属性对应的事件属性信息
class VisualizedPropertyEventProperty {
  String? name;
  String? cname;
  String? type;
  int? snapshotId;
  String? regular;
  String? screenName;
  String? sampleValue;
  String? elementPath;
  String? elementPosition;

  VisualizedPropertyEventProperty.fromJson(Map<String, dynamic> json)
      : name = json['name'],
        cname = json['cname'],
        type = json['type'],
        snapshotId = json['snapshot_id'],
        regular = json['regular'],
        screenName = json['screen_name'],
        sampleValue = json['sample_value'],
        elementPath = json['element_path'],
        elementPosition = json['element_position'];
}
