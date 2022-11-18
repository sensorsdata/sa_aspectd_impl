import 'package:flutter/services.dart';
import 'package:sa_aspectd_impl/common/sensorsdata_page_info.dart';
import 'package:sensors_analytics_flutter_plugin/sensors_analytics_flutter_plugin.dart';

import '../common/sensorsdata_logger.dart';
import 'sensorsdata_visualized_properties.dart';

/// Just for SDK inner used
class SensorsAnalyticsVisualized {
  static bool _isVisualizedConnected = false;
  static String? _propertiesConfig = "";

  static Future<void> visualizedMethodHandler(MethodCall call) async {
    try {
      String method = call.method;
      if ("visualizedConnectionStatusChanged" == method) {
        await updateVisualizedStatus();
        //如果可视化已经连接上了，就进行一次刷新操作
        if (_isVisualizedConnected) {
          PageInfoManager.getInstance().updateWholePageInfo();
          PageInfoManager.getInstance().formatPageElementInfoAndSend();
        } else {
          PageInfoManager.getInstance().clearAll();
        }
      } else if ("visualizedPropertiesConfigChanged" == method) {
        await updateVisualizedPropertiesConfig();
      }
    } catch (e, s) {
      SaLogger.e("SensorsAnalytics Exception Report", stackTrace: s, error: e);
    }
  }

  static void sendVisualizedMessage(String json) {
    ChannelManager.getInstance().methodChannel.invokeMethod("sendVisualizedMessage", [json]);
  }

  ///获取可视化全埋点的状态
  ///如果 sdk 没初始化调用此方法，native 理论上应该返回 false，不要返回异常
  static Future<void> updateVisualizedStatus() async {
    _isVisualizedConnected = await ChannelManager.getInstance().methodChannel.invokeMethod("getVisualizedConnectionStatus");
  }

  static bool get isVisualizedConnected => _isVisualizedConnected;

  static Future<void> updateVisualizedPropertiesConfig() async {
    _propertiesConfig = await ChannelManager.getInstance().methodChannel.invokeMethod("getVisualizedPropertiesConfig");
    VisualizedPropertyManager.getInstance().parseJson(_propertiesConfig);
  }

  static String? get visualizedProperties => _propertiesConfig;
}
