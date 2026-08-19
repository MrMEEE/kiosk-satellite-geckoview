import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kiosk_geckoview/kiosk_geckoview.dart';

enum UserScriptInjectionTime { AT_DOCUMENT_START, AT_DOCUMENT_END }

class UserScript {
	const UserScript({
		required this.source,
		required this.injectionTime,
		this.forMainFrameOnly = true,
	});

	final String source;
	final UserScriptInjectionTime injectionTime;
	final bool forMainFrameOnly;
}

class WebUri {
	WebUri(String value)
			: rawValue = value,
				_uri = Uri.tryParse(value) ?? Uri();

	final String rawValue;
	final Uri _uri;

	String get scheme => _uri.scheme;
	String get host => _uri.host;
	int get port => _uri.port;
	bool get hasScheme => _uri.hasScheme;
	bool get hasPort => _uri.hasPort;
	List<String> get pathSegments => _uri.pathSegments;

	@override
	String toString() => rawValue;
}

class URLRequest {
	const URLRequest({
		this.url,
		this.isForMainFrame = true,
		this.suggestedFilename,
		this.userAgent,
		this.mimeType,
	});

	final WebUri? url;
	final bool? isForMainFrame;
	final String? suggestedFilename;
	final String? userAgent;
	final String? mimeType;
}

enum CacheMode { LOAD_DEFAULT, LOAD_NO_CACHE }

enum MixedContentMode {
	MIXED_CONTENT_ALWAYS_ALLOW,
	MIXED_CONTENT_NEVER_ALLOW,
}

class InAppWebViewSettings {
	const InAppWebViewSettings({
		this.useHybridComposition,
		this.useShouldOverrideUrlLoading,
		this.disableContextMenu,
		this.supportZoom,
		this.builtInZoomControls,
		this.displayZoomControls,
		this.mediaPlaybackRequiresUserGesture,
		this.allowsInlineMediaPlayback,
		this.iframeAllow,
		this.transparentBackground,
		this.geolocationEnabled,
		this.javaScriptCanOpenWindowsAutomatically,
		this.mixedContentMode,
		this.cacheEnabled,
		this.cacheMode,
		this.useOnDownloadStart,
		this.allowBackgroundAudioPlaying,
	});

	final bool? useHybridComposition;
	final bool? useShouldOverrideUrlLoading;
	final bool? disableContextMenu;
	final bool? supportZoom;
	final bool? builtInZoomControls;
	final bool? displayZoomControls;
	final bool? mediaPlaybackRequiresUserGesture;
	final bool? allowsInlineMediaPlayback;
	final String? iframeAllow;
	final bool? transparentBackground;
	final bool? geolocationEnabled;
	final bool? javaScriptCanOpenWindowsAutomatically;
	final MixedContentMode? mixedContentMode;
	final bool? cacheEnabled;
	final CacheMode? cacheMode;
	final bool? useOnDownloadStart;
	final bool? allowBackgroundAudioPlaying;
}

class PullToRefreshSettings {
	const PullToRefreshSettings({this.enabled, this.color});

	final bool? enabled;
	final Color? color;
}

class PullToRefreshController {
	PullToRefreshController({
		required this.settings,
		this.onRefresh,
	});

	PullToRefreshSettings settings;
	final FutureOr<bool> Function()? onRefresh;

	Future<void> setEnabled(bool enabled) async {
		settings = PullToRefreshSettings(enabled: enabled, color: settings.color);
	}

	Future<void> endRefreshing() async {}
}

enum PermissionResourceType { MICROPHONE, CAMERA, GEOLOCATION }

class PermissionRequest {
	const PermissionRequest({required this.resources});

	final List<PermissionResourceType> resources;
}

enum PermissionResponseAction { DENY, GRANT }

class PermissionResponse {
	const PermissionResponse({
		required this.resources,
		required this.action,
	});

	final List<PermissionResourceType> resources;
	final PermissionResponseAction action;
}

enum NavigationActionPolicy { ALLOW, CANCEL }

class NavigationAction {
	const NavigationAction({
		required this.request,
		required this.isForMainFrame,
	});

	final URLRequest request;
	final bool isForMainFrame;
}

class ServerTrustChallenge {
	const ServerTrustChallenge();
}

enum ServerTrustAuthResponseAction { PROCEED, CANCEL }

class ServerTrustAuthResponse {
	const ServerTrustAuthResponse({required this.action});

	final ServerTrustAuthResponseAction action;
}

class WebResourceRequest {
	const WebResourceRequest({
		required this.url,
		this.isForMainFrame,
	});

	final WebUri url;
	final bool? isForMainFrame;
}

class WebResourceError {
	const WebResourceError({required this.description});

	final String description;
}

class WebResourceResponse {
	const WebResourceResponse({this.statusCode});

	final int? statusCode;
}

class WebViewRenderProcessDetail {
	const WebViewRenderProcessDetail({required this.didCrash});

	final bool didCrash;
}

enum WebViewRenderProcessAction { TERMINATE }

enum ConsoleMessageLevel { ERROR, WARNING, DEBUG, TIP, LOG }

class ConsoleMessage {
	const ConsoleMessage({
		required this.message,
		required this.messageLevel,
	});

	final String message;
	final ConsoleMessageLevel messageLevel;
}

enum CompressFormat { JPEG }

class ScreenshotConfiguration {
	const ScreenshotConfiguration({
		required this.compressFormat,
		this.quality,
		this.snapshotWidth,
	});

	final CompressFormat compressFormat;
	final int? quality;
	final double? snapshotWidth;
}

class CookieManager {
	CookieManager._();

	static CookieManager instance() => CookieManager._();

	Future<void> deleteAllCookies() async {}
}

class WebStorageManager {
	WebStorageManager._();

	static WebStorageManager instance() => WebStorageManager._();

	Future<void> deleteAllData() async {}
}

typedef JavaScriptHandlerFunction = FutureOr<Object?> Function(List<dynamic> args);

class InAppWebViewController {
	InAppWebViewController._(this._controller);

	final KioskGeckoViewController _controller;

	static Future<void> clearAllCache() => KioskGeckoViewController.clearAllCache();

	Future<void> loadUrl({required URLRequest urlRequest}) async {
		final url = urlRequest.url?.toString();
		if (url == null || url.isEmpty) return;
		await _controller.loadUrl(url);
	}

	Future<void> reload() async {
		await _controller.reload();
	}

	Future<void> goBack() => _controller.goBack();

	Future<bool> canGoBack() => _controller.canGoBack();

	Future<Object?> evaluateJavascript({required String source}) {
		return _controller.evaluateJavascript(source);
	}

	Future<void> addJavaScriptHandler({
		required String handlerName,
		required JavaScriptHandlerFunction callback,
	}) {
		return _controller.addJavaScriptHandler(
			handlerName: handlerName,
			callback: callback,
		);
	}

	Future<void> pause() => _controller.pause();

	Future<void> resume() => _controller.resume();

	Future<void> resumeTimers() => _controller.resume();

	Future<Uint8List?> takeScreenshot({
		required ScreenshotConfiguration screenshotConfiguration,
	}) {
		return _controller.takeScreenshot(
			quality: screenshotConfiguration.quality ?? 80,
			width: screenshotConfiguration.snapshotWidth,
		);
	}
}

class InAppWebView extends StatefulWidget {
	const InAppWebView({
		super.key,
		this.initialUrlRequest,
		this.initialFile,
		this.initialUserScripts,
		this.pullToRefreshController,
		this.initialSettings,
		this.onReceivedServerTrustAuthRequest,
		this.shouldOverrideUrlLoading,
		this.onWebViewCreated,
		this.onUpdateVisitedHistory,
		this.onLoadStop,
		this.onReceivedError,
		this.onReceivedHttpError,
		this.onDownloadStarting,
		this.onRenderProcessGone,
		this.onRenderProcessUnresponsive,
		this.onRenderProcessResponsive,
		this.onConsoleMessage,
		this.onPermissionRequest,
	});

	final URLRequest? initialUrlRequest;
	final String? initialFile;
	final List<UserScript>? initialUserScripts;
	final PullToRefreshController? pullToRefreshController;
	final InAppWebViewSettings? initialSettings;
	final Future<ServerTrustAuthResponse> Function(
		InAppWebViewController controller,
		ServerTrustChallenge challenge,
	)?
	onReceivedServerTrustAuthRequest;
	final Future<NavigationActionPolicy> Function(
		InAppWebViewController controller,
		NavigationAction action,
	)?
	shouldOverrideUrlLoading;
	final void Function(InAppWebViewController controller)? onWebViewCreated;
	final void Function(InAppWebViewController controller, WebUri? url, bool isReload)?
	onUpdateVisitedHistory;
	final FutureOr<void> Function(InAppWebViewController controller, WebUri? url)?
	onLoadStop;
	final void Function(
		InAppWebViewController controller,
		WebResourceRequest request,
		WebResourceError error,
	)?
	onReceivedError;
	final void Function(
		InAppWebViewController controller,
		WebResourceRequest request,
		WebResourceResponse errorResponse,
	)?
	onReceivedHttpError;
	final FutureOr<Object?> Function(InAppWebViewController controller, URLRequest request)?
	onDownloadStarting;
	final void Function(
		InAppWebViewController controller,
		WebViewRenderProcessDetail detail,
	)?
	onRenderProcessGone;
	final FutureOr<WebViewRenderProcessAction?> Function(
		InAppWebViewController controller,
		WebUri? url,
	)?
	onRenderProcessUnresponsive;
	final FutureOr<WebViewRenderProcessAction?> Function(
		InAppWebViewController controller,
		WebUri? url,
	)?
	onRenderProcessResponsive;
	final void Function(InAppWebViewController controller, ConsoleMessage message)?
	onConsoleMessage;
	final Future<PermissionResponse> Function(
		InAppWebViewController controller,
		PermissionRequest request,
	)?
	onPermissionRequest;

	@override
	State<InAppWebView> createState() => _InAppWebViewState();
}

class _InAppWebViewState extends State<InAppWebView> {
	InAppWebViewController? _controller;
	KioskGeckoViewController? _rawController;

	String? get _initialUrl {
		if (widget.initialUrlRequest != null) {
			return widget.initialUrlRequest!.url.toString();
		}
		final file = widget.initialFile;
		if (file == null || file.isEmpty) return null;
		return 'file:///android_asset/flutter_assets/$file';
	}

	Future<void> _injectScripts(UserScriptInjectionTime timing) async {
		final controller = _controller;
		if (controller == null) return;
		final scripts = widget.initialUserScripts;
		if (scripts == null || scripts.isEmpty) return;
		for (final script in scripts) {
			if (script.injectionTime != timing) continue;
			await controller.evaluateJavascript(source: script.source);
		}
	}

	Future<void> _wireController(KioskGeckoViewController raw) async {
		_rawController = raw;
		final controller = InAppWebViewController._(raw);
		_controller = controller;
		raw.addEventListener('locationChanged', _onLocationChanged);
		raw.addEventListener('pageLoaded', _onPageLoaded);
		widget.onWebViewCreated?.call(controller);
		await _injectScripts(UserScriptInjectionTime.AT_DOCUMENT_START);
		final initial = _initialUrl;
		if (initial != null) {
			await controller.loadUrl(urlRequest: URLRequest(url: WebUri(initial)));
		}
	}

	void _onLocationChanged(Map<String, Object?> payload) {
		final controller = _controller;
		if (controller == null) return;
		final value = payload['url'];
		if (value is! String || value.isEmpty) return;
		widget.onUpdateVisitedHistory?.call(controller, WebUri(value), false);
	}

	void _onPageLoaded(Map<String, Object?> payload) {
		final controller = _controller;
		if (controller == null) return;
		final value = payload['url'];
		if (value is! String || value.isEmpty) return;
		final uri = WebUri(value);
		unawaited(_injectScripts(UserScriptInjectionTime.AT_DOCUMENT_END));
		widget.onUpdateVisitedHistory?.call(controller, uri, false);
		final loadStop = widget.onLoadStop?.call(controller, uri);
		if (loadStop is Future<void>) unawaited(loadStop);
	}

	@override
	void dispose() {
		final raw = _rawController;
		if (raw != null) {
			raw.removeEventListener('locationChanged', _onLocationChanged);
			raw.removeEventListener('pageLoaded', _onPageLoaded);
		}
		super.dispose();
	}

	@override
	Widget build(BuildContext context) {
		return KioskGeckoView(
			initialUrl: _initialUrl,
			onCreated: (controller) {
				unawaited(_wireController(controller));
			},
		);
	}
}