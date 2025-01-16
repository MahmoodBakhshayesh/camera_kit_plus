import 'package:camera_kit_plus/camera_kit_plus_controller.dart';
import 'package:camera_kit_plus/enums.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:camera_kit_plus/camera_kit_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  final _cameraKitPlusPlugin = CameraKitPlus();
  CameraKitPlusController controller = CameraKitPlusController();

  @override
  void initState() {
    super.initState();
    // initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String platformVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    // We also handle the message potentially returning null.
    try {
      platformVersion = await _cameraKitPlusPlugin.getPlatformVersion() ?? 'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.blueAccent,
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                  child: CameraKitOcrPlusView(
                controller: controller,

                onTextRead: (OcrData data) {
                  print(data.toJson());
                },
              )),
              Expanded(
                child: Container(
                  color: Colors.red,
                  child: Column(
                    children: [
                      TextButton(
                        onPressed: () {
                          controller.pauseCamera();
                        },
                        child: Text("Pause"),
                      ),
                      TextButton(
                        onPressed: () {
                          controller.resumeCamera();
                        },
                        child: Text("Continue"),
                      ),
                      TextButton(
                        onPressed: () {
                          controller.changeFlashMode(CameraKitPlusFlashMode.off);
                        },
                        child: Text("off"),
                      ),
                      TextButton(
                        onPressed: () {
                          controller.changeFlashMode(CameraKitPlusFlashMode.on);
                        },
                        child: Text("on"),
                      ),
                      TextButton(
                        onPressed: () {
                          controller.switchCamera(CameraKitPlusCameraMode.back);
                        },
                        child: Text("back"),
                      ),
                      TextButton(
                        onPressed: () {
                          controller.switchCamera(CameraKitPlusCameraMode.front);
                        },
                        child: Text("front"),
                      ),
                    ],
                  ),
                ),
              ),
              Text('Running on: $_platformVersion\n'),
            ],
          ),
        ),
      ),
    );
  }
}
