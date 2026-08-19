import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

typedef KioskGeckoViewCreated = void Function(KioskGeckoViewController controller);
typedef KioskGeckoJsHandler = FutureOr<Object?> Function(List<dynamic> args);
typedef KioskGeckoEventHandler = void Function(Map<String, Object?> payload);

class KioskGeckoViewController {
  KioskGeckoViewController._(int id)
      : _channel = MethodChannel('kiosk_satellite/geckoview_$id') {
    _channel.setMethodCallHandler(_handleCallback);
  }

  final MethodChannel _channel;
  final Map<String, KioskGeckoJsHandler> _handlers = {};
  final Map<String, Set<KioskGeckoEventHandler>> _eventHandlers = {};

  static const _globalChannel = MethodChannel('kiosk_satellite/geckoview_global');

  static Future<void> clearAllCache() async {
    await _globalChannel.invokeMethod<void>('clearAllCache');
  }

  Future<void> loadUrl(String url) async {
    await _channel.invokeMethod<void>('loadUrl', {'url': url});
  }

  Future<void> reload() async {
    await _channel.invokeMethod<void>('reload');
  }

  Future<void> goBack() async {
    await _channel.invokeMethod<void>('goBack');
  }

  Future<bool> canGoBack() async {
    return (await _channel.invokeMethod<bool>('canGoBack')) ?? false;
  }

  Future<Object?> evaluateJavascript(String source) async {
    return _channel.invokeMethod<Object?>('evaluateJavascript', {
      'source': source,
    });
  }

  Future<void> pause() async {
    await _channel.invokeMethod<void>('pause');
  }

  Future<void> resume() async {
    await _channel.invokeMethod<void>('resume');
  }

  Future<Uint8List?> takeScreenshot({int quality = 80, double? width}) async {
    final bytes = await _channel.invokeMethod<Uint8List>('takeScreenshot', {
      'quality': quality,
      'width': width,
    });
    return bytes;
  }

  Future<void> addJavaScriptHandler({
    required String handlerName,
    required KioskGeckoJsHandler callback,
  }) async {
    _handlers[handlerName] = callback;
    await _channel.invokeMethod<void>('registerJsHandler', {
      'handlerName': handlerName,
    });
  }

  Future<void> removeJavaScriptHandler(String handlerName) async {
    _handlers.remove(handlerName);
    await _channel.invokeMethod<void>('unregisterJsHandler', {
      'handlerName': handlerName,
    });
  }

  void addEventListener(String event, KioskGeckoEventHandler handler) {
    _eventHandlers.putIfAbsent(event, () => <KioskGeckoEventHandler>{}).add(handler);
  }

  void removeEventListener(String event, KioskGeckoEventHandler handler) {
    final handlers = _eventHandlers[event];
    if (handlers == null) return;
    handlers.remove(handler);
    if (handlers.isEmpty) _eventHandlers.remove(event);
  }

  Future<Object?> _handleCallback(MethodCall call) async {
    if (call.method == 'event') {
      final data = (call.arguments as Map?)?.cast<String, Object?>();
      final name = data?['name'] as String?;
      final payload = (data?['payload'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{};
      if (name != null) {
        final handlers = _eventHandlers[name]?.toList(growable: false) ??
            const <KioskGeckoEventHandler>[];
        for (final handler in handlers) {
          handler(payload);
        }
      }
      return null;
    }

    if (call.method != 'jsHandler') return null;
    final data = (call.arguments as Map?)?.cast<String, Object?>();
    final name = data?['handlerName'] as String?;
    if (name == null) return null;
    final args = (data?['args'] as List?)?.toList() ?? const <dynamic>[];
    final handler = _handlers[name];
    if (handler == null) return null;
    return handler(args);
  }
}

class KioskGeckoView extends StatelessWidget {
  const KioskGeckoView({
    super.key,
    this.initialUrl,
    this.onCreated,
  });

  final String? initialUrl;
  final KioskGeckoViewCreated? onCreated;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }

    return AndroidView(
      viewType: 'kiosk_satellite/geckoview',
      creationParams: <String, Object?>{'initialUrl': initialUrl},
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (id) {
        onCreated?.call(KioskGeckoViewController._(id));
      },
    );
  }
}
