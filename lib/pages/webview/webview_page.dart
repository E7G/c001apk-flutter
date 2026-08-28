import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import '../../constants/constants.dart';
import '../../utils/cache_util.dart';
import '../../utils/extensions.dart';
import '../../utils/global_data.dart';
import '../../utils/storage_util.dart';
import '../../utils/utils.dart';

// ignore: constant_identifier_names
enum WebviewMenuItem { Refresh, Copy, Open_In_Browser, Clear_Cache, Go_Back }

class WebviewPage extends StatefulWidget {
  const WebviewPage({super.key});

  @override
  State<WebviewPage> createState() => _WebviewPageState();
}

class _WebviewPageState extends State<WebviewPage> {
  final String _url = Get.parameters['url'] ?? '';
  final bool _isLogin = Get.parameters['isLogin'] == '1';
  final _titleStream = StreamController<String?>();
  final _progressStream = StreamController<double>();

  InAppWebViewController? _webViewController;
  late final Future<void> _cookieReady;
  bool _loginFinished = false;

  @override
  void initState() {
    super.initState();
    _cookieReady = _prepareCookies();
  }

  Future<void> _prepareCookies() async {
    final cookieManager = CookieManager();

    // Login should always start from a clean web session. Await the deletion
    // to avoid racing with the first navigation and deleting fresh cookies.
    if (_isLogin) {
      await cookieManager.deleteAllCookies();
      await cookieManager.setCookie(
        url: WebUri.uri(Uri.parse('https://account.coolapk.com/')),
        name: 'forward',
        value: Constants.URL_COOLAPK,
      );
      if (GStorage.szlmId.isNotEmpty) {
        await cookieManager.setCookie(
          url: WebUri.uri(Uri.parse('https://account.coolapk.com/')),
          name: 'DID',
          value: GStorage.szlmId,
        );
      }
      return;
    }

    if (GlobalData().isLogin) {
      final url = WebUri.uri(Uri.parse(Constants.URL_COOLAPK));
      if (GStorage.szlmId.isNotEmpty) {
        await cookieManager.setCookie(
          url: url,
          name: 'DID',
          value: GStorage.szlmId,
        );
      }
      await cookieManager.setCookie(
        url: url,
        name: 'displayVersion',
        value: 'v14',
      );
      await cookieManager.setCookie(
        url: url,
        name: 'uid',
        value: GlobalData().uid,
      );
      await cookieManager.setCookie(
        url: url,
        name: 'username',
        value: GlobalData().username,
      );
      await cookieManager.setCookie(
        url: url,
        name: 'token',
        value: GlobalData().token,
      );
      if (GlobalData().SESSID.startsWith('SESSID=')) {
        await cookieManager.setCookie(
          url: url,
          name: 'SESSID',
          value: GlobalData().SESSID.substring('SESSID='.length),
        );
      }
    }
  }

  Future<bool> _tryCompleteLogin() async {
    if (!_isLogin || _loginFinished) {
      return false;
    }

    final cookieManager = CookieManager();
    final cookieUrls = <String>[
      Constants.URL_COOLAPK,
      'https://account.coolapk.com/',
    ];

    String? uid;
    String? username;
    String? token;
    String? sessid;

    for (final cookieUrl in cookieUrls) {
      final url = WebUri.uri(Uri.parse(cookieUrl));
      uid ??= (await cookieManager.getCookie(url: url, name: 'uid'))?.value;
      username ??=
          (await cookieManager.getCookie(url: url, name: 'username'))?.value;
      token ??=
          (await cookieManager.getCookie(url: url, name: 'token'))?.value;
      sessid ??=
          (await cookieManager.getCookie(url: url, name: 'SESSID'))?.value;
    }

    if (uid.isNullOrEmpty || username.isNullOrEmpty || token.isNullOrEmpty) {
      return false;
    }

    _loginFinished = true;
    GStorage.setUid(uid!);
    GStorage.setUsername(username!);
    GStorage.setToken(token!);
    GStorage.setSessid(
      sessid.isNullOrEmpty ? '' : 'SESSID=$sessid',
    );
    GStorage.setIsLogin(true);

    if (mounted) {
      Get.back(result: true);
    }
    return true;
  }

  @override
  void dispose() {
    _titleStream.close();
    _progressStream.close();
    _webViewController = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder(
          initialData: null,
          stream: _titleStream.stream,
          builder: (_, snapshot) => snapshot.data != null
              ? Text(
                  snapshot.data!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : const SizedBox.shrink(),
        ),
        bottom: PreferredSize(
          preferredSize: Size.zero,
          child: StreamBuilder(
            initialData: 0.0,
            stream: _progressStream.stream,
            builder: (_, snapshot) => snapshot.data as double < 1
                ? LinearProgressIndicator(
                    value: snapshot.data as double,
                  )
                : const SizedBox.shrink(),
          ),
        ),
        actions: [
          PopupMenuButton(
            onSelected: (item) async {
              switch (item) {
                case WebviewMenuItem.Refresh:
                  _webViewController?.reload();
                  break;
                case WebviewMenuItem.Copy:
                  WebUri? uri = await _webViewController?.getUrl();
                  if (uri != null) {
                    Utils.copyText(uri.toString());
                  }
                  break;
                case WebviewMenuItem.Open_In_Browser:
                  WebUri? uri = await _webViewController?.getUrl();
                  if (uri != null) {
                    Utils.launchURL(uri.toString());
                  }
                  break;
                case WebviewMenuItem.Clear_Cache:
                  try {
                    await InAppWebViewController.clearAllCache();
                    await _webViewController?.clearHistory();
                    SmartDialog.showToast('已清理');
                  } catch (e) {
                    SmartDialog.showToast(e.toString());
                  }
                  break;
                case WebviewMenuItem.Go_Back:
                  if (await _webViewController?.canGoBack() == true) {
                    _webViewController?.goBack();
                  }
                  break;
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<WebviewMenuItem>>[
              ...WebviewMenuItem.values.sublist(0, 4).map(
                  (item) => PopupMenuItem(
                    value: item,
                    child: Text(switch (item) {
                      WebviewMenuItem.Refresh => '刷新',
                      WebviewMenuItem.Copy => '复制链接',
                      WebviewMenuItem.Open_In_Browser => '在浏览器中打开',
                      WebviewMenuItem.Clear_Cache => '清除缓存',
                      WebviewMenuItem.Go_Back => '返回',
                    }),
                  )),
              const PopupMenuDivider(),
              PopupMenuItem(
                  value: WebviewMenuItem.Go_Back,
                  child: Text(
                    '返回',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  )),
            ],
          )
        ],
      ),
      body: FutureBuilder<void>(
        future: _cookieReady,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('初始化登录环境失败：${snapshot.error}'),
              ),
            );
          }
          return InAppWebView(
        initialSettings: InAppWebViewSettings(
          useHybridComposition: false,
          mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
          useShouldOverrideUrlLoading: true,
          useOnDownloadStart: true,
          clearCache: true,
          userAgent: GStorage.userAgent,
          forceDark: ForceDark.AUTO,
          algorithmicDarkeningAllowed: true,
        ),
        initialUrlRequest:
            URLRequest(url: WebUri.uri(Uri.parse(_url)), headers: {
          'X-Requested-With': Constants.APP_ID,
        }),
        onWebViewCreated: (InAppWebViewController controller) {
          _webViewController = controller;
        },
        onProgressChanged: (controller, progress) {
          _progressStream.add(progress / 100);
        },
        onTitleChanged: (controller, title) {
          _titleStream.add(title);
        },
        onCloseWindow: (controller) => Get.back(),
        shouldOverrideUrlLoading: (controller, navigationAction) async {
          var url = navigationAction.request.url!.toString();

          if (!url.startsWith('http')) {
            var snackBar = SnackBar(
              content: const Text('当前网页将要打开外部链接，是否打开'),
              showCloseIcon: true,
              action: SnackBarAction(
                label: '打开',
                onPressed: () => Utils.launchURL(url),
              ),
            );
            ScaffoldMessenger.of(context).showSnackBar(snackBar);
            return NavigationActionPolicy.CANCEL;
          }

          if (_isLogin && await _tryCompleteLogin()) {
            return NavigationActionPolicy.CANCEL;
          }

          return NavigationActionPolicy.ALLOW;
        },
        onLoadStop: (controller, url) async {
          if (_isLogin) {
            await _tryCompleteLogin();
          }
        },
        onDownloadStartRequest: (controller, request) {
          showDialog(
              context: context,
              builder: (context) {
                String suggestedFilename = request.suggestedFilename.toString();
                String fileSize =
                    CacheManage.formatSize(request.contentLength.toDouble());
                try {
                  suggestedFilename = Uri.decodeComponent(suggestedFilename);
                } catch (e) {
                  debugPrint(e.toString());
                }
                return AlertDialog(
                  title: Text(
                    '下载文件：$suggestedFilename？',
                    style: const TextStyle(fontSize: 18),
                  ),
                  content: SelectableText(request.url.toString()),
                  actions: [
                    TextButton(
                        onPressed: () => Get.back(),
                        child: const Text('关闭')),
                    TextButton(
                        onPressed: () async {
                          Get.back();
                          Utils.onDownloadFile(
                            request.url.toString(),
                            suggestedFilename,
                          );
                        },
                        child: Text('确定（$fileSize）')),
                  ],
                );
              });
          _progressStream.add(1);
        },
      );
        },
      ),
    );
  }
}
