import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:sa_aspectd_impl/viewscreen/sensorsdata_viewscreen_tabbar.dart';

import 'common/sensorsdata_logger.dart';
import 'viewscreen/sensorsdata_viewscreen_route.dart';
import 'visualized/sensorsdata_visualized.dart';

@pragma("vm:entry-point")
class SensorsDataAPI {
  static final _instance = SensorsDataAPI._();

  SensorsDataAPI._();

  factory SensorsDataAPI.getInstance() => _instance;

  void updateRoute() {
    VisualizedStatusManager.getInstance().handleVisualizedInfo();
  }

  ///通过 [SchedulerBinding.instance?.addPersistentFrameCallback] 添加的回调
  void persistentFrameCallback(Duration timeStamp) {
    try {
      RouteViewScreenResolver.getInstance().persistentFrameCallback(timeStamp);
      TabViewScreenResolver.getInstance().persistentFrameCallback(timeStamp);
    } catch (e, s) {
      SaLogger.e("SensorsAnalytics Exception Report", stackTrace: s, error: e);
    }
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
    this.isProject,
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
  final bool? isProject;

  bool isProjectRoot() => isProject ?? false;

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
      json['parameterLocations'] = parameterLocations!.map<Map<String, Object?>>((_SALocation location) => location.toJsonMap()).toList();
    }
    return json;
  }

  @override
  String toString() {
    return '_SALocation{rootUrl: $rootUrl, importUri: $importUri, file: $file, line: $line, column: $column, name: $name, parameterLocations: $parameterLocations}';
  }
}

bool isProjectCreatedElement(Element element) {
  if (element.widget is _SAHasCreationLocation) {
    _SAHasCreationLocation hasCreationLocation = element.widget as _SAHasCreationLocation;
    return hasCreationLocation._salocation.isProjectRoot();
  }
  return false;
}

bool hasCreationLocation(Widget? widget) {
  if (widget == null) {
    return false;
  }
  return widget is _SAHasCreationLocation;
}

Map<String, dynamic> getLocationInfo(Widget widget) {
  _SAHasCreationLocation location = widget as _SAHasCreationLocation;
  Map<String, dynamic> result = {};
  result["file"] = location._salocation.file;
  result["rootUrl"] = location._salocation.rootUrl;
  result["importUri"] = location._salocation.importUri;
  result["isProjectRoot"] = location._salocation.isProjectRoot();
  return result;
}
