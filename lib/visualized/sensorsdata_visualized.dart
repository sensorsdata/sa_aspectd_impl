import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sa_aspectd_impl/common/sensorsdata_common.dart';
import 'package:sa_aspectd_impl/common/sensorsdata_page_info.dart';
import 'package:sa_aspectd_impl/viewscreen/sensorsdata_viewscreen.dart';
import 'package:sa_aspectd_impl/viewscreen/sensorsdata_viewscreen_route.dart';
import 'package:sa_aspectd_impl/visualized/sensorsdata_visualized_channel.dart';
import 'package:sensors_analytics_flutter_plugin/sensors_analytics_flutter_plugin.dart';

import '../common/sensorsdata_logger.dart';

///可视化全埋点状态管理
///1.注册 Channel
///2.更新可视化连接状态
class VisualizedStatusManager {
  static final _instance = VisualizedStatusManager._();

  VisualizedStatusManager._();

  factory VisualizedStatusManager.getInstance() => _instance;

  /// 用于标记是否已经主动请求过一次状态和配置信息
  bool _hasCheckedStatusAndConfig = false;

  ///自定义属性中用于更新当前页面是否应该更新
  bool _shouldUpdate = false;

  ///每次界面元素刷新，都会调用这个方法
  void handleVisualizedInfo() async {
    try {
      setMethodHandler();
      if (!_hasCheckedStatusAndConfig) {
        _hasCheckedStatusAndConfig = true;
        //第一次注册后，更新状态可自定义属性
        await SensorsAnalyticsVisualized.updateVisualizedStatus();
        await SensorsAnalyticsVisualized.updateVisualizedPropertiesConfig();
      }
    } catch (e, s) {
      SaLogger.e("SensorsAnalytics Exception Report", stackTrace: s, error: e);
    }
  }

  ///设置监听 native 的状态变更
  bool _hasSetHandler = false;

  void setMethodHandler() {
    if (!_hasSetHandler) {
      ChannelManager.getInstance().methodChannel.setMethodCallHandler(SensorsAnalyticsVisualized.visualizedMethodHandler);
      _hasSetHandler = true;
    }
  }

  //以下是用于触发刷新上报的时机
  Timer? _timer;
  BuildContext? _lastExecuteBuildContext;
  Element? _mountElement;

  ///当渲染结束的时候记录
  void handleDrawFrame() {
    //只有在连接上可视化功能的时候才会进行页面元素遍历
    if (SensorsAnalyticsVisualized.isVisualizedConnected) {
      if (_timer != null && _timer!.isActive) {
        _timer!.cancel();
      }
      scheduleTask();
    }
  }

  ///页面树更新的时候，通常由上而下，这里会获取第一个元素，作为这个子树的根
  ///这棵树下面的所有节点都会被替换掉
  void mount(Element? parent) {
    if (_shouldUpdatePageInfo()) {
      if (_mountElement == null) {
        _mountElement = parent;
      }
      if (_timer != null && _timer!.isActive) {
        _timer!.cancel();
      }
      scheduleTask();
    }
  }

  ///当所有结束的时候
  void unmount() {
    if (_shouldUpdatePageInfo()) {
      if (_timer != null && _timer!.isActive) {
        _timer!.cancel();
      }
      scheduleTask();
    }
  }

  void scheduleTask() {
    try {
      //TODO  100ms 也需要进一步的优化
      _timer = Timer(Duration(milliseconds: 100), () {
        bool isWholeUpdated = false;
        //只有可视化前端连接的情况下，才会进入此逻辑
        if (SensorsAnalyticsVisualized.isVisualizedConnected) {
          if (_lastExecuteBuildContext == null || _lastExecuteBuildContext != RouteViewScreenResolver.getInstance().lastViewScreenContext) {
            _lastExecuteBuildContext = RouteViewScreenResolver.getInstance().lastViewScreenContext;
            if (_lastExecuteBuildContext != null) {
              PageInfoManager.getInstance().updateWholePageInfo();
              isWholeUpdated = true;
            }
          }
        }

        //TODO 这部分还需要进一步的优化，做到只更新部分节点
        if (_mountElement != null && !isWholeUpdated && _shouldUpdatePageInfo()) {
          PageInfoManager.getInstance().updateWholePageInfo();
        }
        //只有在可视化前端连接的情况下，才会发送可视化页面元素信息
        if (SensorsAnalyticsVisualized.isVisualizedConnected) {
          PageInfoManager.getInstance().formatPageElementInfoAndSend();
        }
        _mountElement = null;
        _timer = null;
      });
    } catch (e, s) {
      SaLogger.e("SensorsAnalytics Exception Report", stackTrace: s, error: e);
    }
  }

  ///判断是否应该更新页面信息
  bool _shouldUpdatePageInfo() {
    if (SensorsAnalyticsVisualized.isVisualizedConnected || this._shouldUpdate) {
      return true;
    }
    return false;
  }

  ///档切换页面的时候需要将其值设置为 false，
  ///当点击发生的时候并且页面中存在自定义属性配置的时候就删除掉。
  void updatePageRefresh(bool shouldUpdate, {bool forceUpdate = false}) {
    try {
      if (forceUpdate) {
        PageInfoManager.getInstance().updateWholePageInfo();
        scheduleTask();
        return;
      }
      //当触发第一个点击事件的时候，做一次更新操作
      if (!this._shouldUpdate && shouldUpdate) {
        PageInfoManager.getInstance().updateWholePageInfo();
      }
      this._shouldUpdate = shouldUpdate;
    } catch (e, s) {
      SaLogger.e("SensorsAnalytics Exception Report", stackTrace: s, error: e);
    }
  }
}

///下面都是一些与可视化相关的配置信息
///1.Visualized Page Info
@pragma("vm:entry-point")
abstract class VisualizedType {
  String callType();

  Map<String, dynamic> toJson();
}

@pragma("vm:entry-point")
class VisualizedElementType extends VisualizedType {
  List<VisualizedItemInfo> data = [];

  @override
  Map<String, dynamic> toJson() {
    Map<String, dynamic> jsonMap = {};
    jsonMap["callType"] = callType();
    jsonMap["data"] = data;
    return jsonMap;
  }

  @override
  String callType() => "visualized_track";
}

@pragma("vm:entry-point")
class VisualizedScreenType extends VisualizedType {
  ViewScreenEvent? screenInfo;

  @override
  String callType() => "page_info";

  @override
  Map<String, dynamic> toJson() {
    Map<String, dynamic> jsonMap = {};
    jsonMap["callType"] = callType();
    if (screenInfo != null) {
      Map<String, dynamic> screenData = {};
      screenData["screen_name"] = screenInfo?.finalScreenName;
      screenData["title"] = screenInfo?.finalTitle;
      screenData["lib_version"] = SAUtils.FLUTTER_AUTOTRACK_VERSION;
      jsonMap["data"] = screenData;
    }
    return jsonMap;
  }
}

@pragma("vm:entry-point")
class VisualizedItemInfo {
  String? elementContent;
  String? elementPath;
  String? title;
  String? screenName;
  int level = 0;
  double left = 0;
  double top = 0;
  double height = 0;
  double width = 0;
  String? id;
  bool clickable = false;
  int? elementPosition;
  bool? isListView;
  List<String>? subElements;

  Map<String, dynamic> toJson() {
    Map<String, dynamic> jsonMap = {"level": level, "left": left, "top": top, "height": height, "width": width, "enable_click": clickable};
    if (elementContent != null) {
      jsonMap[r"$element_content"] = elementContent;
    }
    if (elementPath != null) {
      jsonMap[r"$element_path"] = elementPath;
    }
    if (elementPosition != null) {
      jsonMap[r"$element_position"] = "$elementPosition";
    }
    if (title != null) {
      jsonMap["title"] = title;
    }
    if (screenName != null) {
      jsonMap["screen_name"] = screenName;
    }
    if (id != null) {
      jsonMap["id"] = id;
    }
    if (subElements != null) {
      jsonMap["subelements"] = subElements;
    }
    if (isListView != null) {
      jsonMap["is_list_view"] = isListView;
    }
    return jsonMap;
  }
}
