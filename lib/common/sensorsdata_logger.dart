//log info
import 'dart:developer';

enum LOG_LEVEL { DEBUG, INFO, WARN, ERROR, NO_LOG }

/// A simple helper class for printing log to console
@pragma("vm:entry-point")
class SaLogger {
  static LOG_LEVEL _logLevel = LOG_LEVEL.WARN;
  static const TAG = "SensorsDataAnalytics Flutter";

  static set level(LOG_LEVEL level){
    _logLevel = level;
  }

  static void d(String str) {
    if (LOG_LEVEL.DEBUG.index >= _logLevel.index) _developerLog(str);
  }

  static void i(String str) {
    if (LOG_LEVEL.INFO.index >= _logLevel.index) _developerLog(str);
  }

  static void w(String str) {
    if (LOG_LEVEL.WARN.index >= _logLevel.index) _developerLog(str);
  }

  static void e(String str, {StackTrace? stackTrace, Object? error}) {
    _developerLog(str, stackTrace: stackTrace ?? StackTrace.current, error: error);
  }

  static void _developerLog(String msg, {StackTrace? stackTrace, Object? error}) {
    assert((){
      log(msg, name: "SensorsAnalytics Log: ${DateTime.now().toLocal().toString()}", error: error, stackTrace: stackTrace);
      return true;
    }());
  }

  /// Call print method to show message
  /// use print() method for logging, the log message may be truncated.
  static void p(String str) {
    if (LOG_LEVEL.DEBUG.index >= _logLevel.index) assert((){
      print(str);
      return true;
    }());
  }
}
