import 'dart:async';
import 'dart:io';
import 'package:android_system_font/android_system_font.dart';
import 'package:flutter/services.dart';

class NativeFeatures {
  static bool _systemFontLoaded = false;

  static Future<ByteData> _readFileBytes(String path) async {
    final bytes = await File(path).readAsBytes();
    return ByteData.view(bytes.buffer);
  }

  static Future<void> loadSystemFont() async {
    if (_systemFontLoaded) return;
    final fontLoader = FontLoader('SystemFont');
    final fontFilePath = await AndroidSystemFont().getFilePath();
    fontLoader.addFont(_readFileBytes(fontFilePath!));
    await fontLoader.load();
    _systemFontLoaded = true;
  }
}
