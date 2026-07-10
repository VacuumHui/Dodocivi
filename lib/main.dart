import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sdxl_collector/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const SdxlCollectorApp());
}
