///提供一些用于配置全埋点逻辑的方式
class SensorsAnalyticsAutoTrackConfig {
  static final _instance = SensorsAnalyticsAutoTrackConfig._();

  SensorsAnalyticsAutoTrackConfig._();

  factory SensorsAnalyticsAutoTrackConfig.getInstance() => _instance;

  ///用于配置全埋点是否自动处理 TabBar 对应的 PageView.
  ///若采集存在不准确的地方，请设置为 false，并由开发者自行处理 TabBar 对应的页面浏览
  bool isTabBarPageViewEnabled = true;
}

