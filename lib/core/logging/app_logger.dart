import 'package:logger/logger.dart';

class AppLogger {
  AppLogger._();

  static final Logger _logger = Logger(
    filter: ProductionFilter(),
    printer: PrettyPrinter(
      methodCount: 0,
      lineLength: 100,
      printEmojis: false,
      noBoxingByDefault: true,
    ),
  );

  static void debug(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.d(message, error: error, stackTrace: stackTrace);
  }

  static void info(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  static void warn(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  static void error(Object error, {StackTrace? stackTrace, String? message}) {
    _logger.e(
      message ?? 'Unexpected error',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
