import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:local_assets_server/local_assets_server.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:webview_jsbridge_x/webview_jsbridge_x.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomeView('es5'),
    );
  }
}

class HomeView extends StatefulWidget {
  final String title;
  HomeView(this.title) : super();

  @override
  _HomeViewState createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final jsBridge = WebViewJSBridgeX();
  late final WebViewController _controller;

  bool isListening = false;
  String? address;
  int? port;

  @override
  initState() {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final WebViewController controller =
        WebViewController.fromPlatformCreationParams(params);

    final isEs5 = widget.title == 'es5';
    final jsVersion =
        isEs5 ? WebViewXInjectJsVersion.es5 : WebViewXInjectJsVersion.es7;
    final htmlVersion = isEs5 ? 'default' : 'async';

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            debugPrint('WebView is loading (progress : $progress%)');
          },
          onPageStarted: (String url) {
            debugPrint('Page started loading: $url');
          },
          onPageFinished: (String url) {
            jsBridge.injectJs(esVersion: jsVersion);
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('''
Page resource error:
  code: ${error.errorCode}
  description: ${error.description}
  errorType: ${error.errorType}
  isForMainFrame: ${error.isForMainFrame}
          ''');
          },
          onNavigationRequest: (NavigationRequest request) {
            if (request.url.contains('__bridge_loaded__')) {
              jsBridge.injectJs(esVersion: jsVersion);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse('http://$address:$port/$htmlVersion.html'));

    jsBridge.jsChannels.forEach((channel) {
      controller.addJavaScriptChannel(channel.name,
          onMessageReceived: channel.onMessageReceived);
    });

    jsBridge.controller = controller;
    jsBridge.defaultHandler = _defaultHandler;
    jsBridge.registerHandler("NativeEcho", _nativeEchoHandler);

    _initServer();
    super.initState();
  }

  Future<void> _initServer() async {
    final server = LocalAssetsServer(
      address: InternetAddress.loopbackIPv4,
      assetsBasePath: 'assets/',
      logger: DebugLogger(),
    );

    final address = await server.serve();

    setState(() {
      this.address = address.address;
      port = server.boundPort!;
      isListening = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.title == 'es5')
            TextButton(
              child: Text(
                'es7',
                style: TextStyle(color: Colors.red),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => HomeView('es7'),
                ),
              ),
            ),
        ],
      ),
      body: isListening
          ? Row(
              children: [
                Expanded(
                  child: _buildWebView(),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text('native'),
                      TextButton(
                        child: Text(
                          'sendHello',
                        ),
                        onPressed: () => _sendHello(),
                      ),
                      TextButton(
                        child: Text(
                          'callJSEcho',
                        ),
                        onPressed: () => _callJSEcho(),
                      ),
                      TextButton(
                        child: Text(
                          '_callNotExist',
                        ),
                        onPressed: () => _callNotExist(),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Center(child: CircularProgressIndicator()),
    );
  }

  WebViewWidget _buildWebView() {
    return WebViewWidget(
      controller: _controller,
    );
  }

  Future<void> _sendHello() async {
    final res = await jsBridge.send('hello from native');
    print('_sendHello res: $res');
  }

  Future<void> _callJSEcho() async {
    final res =
        await jsBridge.callHandler('JSEcho', data: 'callJs from native');
    print('_callJSEcho res: $res');
  }

  Future<void> _callNotExist() async {
    final res =
        await jsBridge.callHandler('NotExist', data: 'callJs from native');
    print('_callNotExist res: $res');
  }

  Future<Object?> _defaultHandler(Object? data) async {
    await Future.delayed(Duration(seconds: 1), () {});
    return '_defaultHandler res from native';
  }

  Future<Object?> _nativeEchoHandler(Object? data) async {
    await Future.delayed(Duration(seconds: 1), () {});
    return '_nativeEchoHandler res from native';
  }
}
