import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart'; 
import 'package:app_links/app_links.dart'; 
import 'package:path_provider/path_provider.dart'; 
import 'package:open_filex/open_filex.dart'; 
import 'package:flutter_pdfview/flutter_pdfview.dart'; // PDF Viewer ke liye
import 'package:home_widget/home_widget.dart'; // Home Screen Widget ke liye

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Background Notification Handler
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("Background message received: ${message.messageId}");
  // Background mein notification aane par count badhana
  SharedPreferences prefs = await SharedPreferences.getInstance();
  int currentCount = prefs.getInt('notif_count') ?? 0;
  await prefs.setInt('notif_count', currentCount + 1);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  runApp(const MyProWebApp());
}

class MyProWebApp extends StatelessWidget {
  const MyProWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TodayVacancy', 
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

// ==========================================
// NAVIGATION SCREEN
// ==========================================
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  int _refreshCounter = 0; 
  int _notificationBadgeCount = 0; // Notification badge count
  
  String myWebsite = 'https://todayvacancy.in';

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  final GlobalKey<WebViewTabState> _homeWebViewKey = GlobalKey<WebViewTabState>();

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
    _setupPushNotifications();
    _loadNotificationBadge();
    _initHomeWidget();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  // Home Screen Widget se click handle karna
  void _initHomeWidget() {
    HomeWidget.setAppGroupId('com.todayvacancy.in');
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_launchedFromWidget);
    HomeWidget.widgetClicked.listen(_launchedFromWidget);
  }

  void _launchedFromWidget(Uri? uri) {
    if (uri != null && uri.host == 'search') {
      // Agar widget se search dabaya hai
      _handleIncomingLink('https://todayvacancy.in/?s=');
    }
  }

  // SharedPreferences se notification count load karna
  Future<void> _loadNotificationBadge() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _notificationBadgeCount = prefs.getInt('notif_count') ?? 0;
    });
  }

  // Notification tab kholne par badge clear karna
  Future<void> _clearNotificationBadge() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_count', 0);
    setState(() {
      _notificationBadgeCount = 0;
    });
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleIncomingLink(initialUri.toString());
      }
    } catch (e) {
      debugPrint("Deep Link Error: $e");
    }

    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      if (uri != null) {
        _handleIncomingLink(uri.toString());
      }
    });
  }

  void _handleIncomingLink(String url) {
    setState(() {
      myWebsite = url;
      _currentIndex = 0; 
    });
    _homeWebViewKey.currentState?.loadCustomUrl(url);
  }

  void _setupPushNotifications() async {
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      await messaging.subscribeToTopic("all_users");

      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        // App open hote waqt notification aaye toh badge badhao
        SharedPreferences prefs = await SharedPreferences.getInstance();
        int currentCount = prefs.getInt('notif_count') ?? 0;
        await prefs.setInt('notif_count', currentCount + 1);
        _loadNotificationBadge();

        if (message.notification != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("${message.notification!.title}: ${message.notification!.body}"), backgroundColor: Colors.deepPurple)
          );
        }
      });
    } catch (e) {
      debugPrint("Notification error: $e");
    }
  }

  void _changeTab(int index) {
    setState(() {
      _currentIndex = index;
      _refreshCounter++;
      if (index == 1) { // 1 index Notifications ka hai
        _clearNotificationBadge();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        
        if (_currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
            _refreshCounter++;
          });
          return;
        }

        final bool canGoBack = await _homeWebViewKey.currentState?.canGoBack() ?? false;
        if (canGoBack) {
          _homeWebViewKey.currentState?.goBack();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            WebViewTab(
              key: _homeWebViewKey,
              url: myWebsite, 
              isOffline: false,
              onGoToDownloads: () => _changeTab(3), 
              onTabChange: _changeTab,
            ),
            WebViewTab(
              url: 'https://todayvacancy.in/notification', 
              isOffline: false,
              onGoToDownloads: () => _changeTab(3),
              onTabChange: _changeTab,
            ),
            LikedTab(
              refreshToken: _refreshCounter,
              onTabChange: _changeTab,
            ),
            DownloadedTab(
              refreshToken: _refreshCounter,
              onTabChange: _changeTab,
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _changeTab,
          destinations: [
            const NavigationDestination(icon: Icon(Icons.public), label: 'Home'),
            NavigationDestination(
              icon: Badge(
                label: Text('$_notificationBadgeCount'),
                isLabelVisible: _notificationBadgeCount > 0,
                child: const Icon(Icons.notifications),
              ), 
              label: 'Alerts'
            ), 
            const NavigationDestination(icon: Icon(Icons.favorite), label: 'Liked'),
            const NavigationDestination(icon: Icon(Icons.download_done), label: 'Downloads'),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 3-LINE NAVIGATION DRAWER
// ==========================================
class AppSideDrawer extends StatelessWidget {
  final Function(int) onTabChange;
  
  const AppSideDrawer({super.key, required this.onTabChange});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const UserAccountsDrawerHeader(
            decoration: BoxDecoration(
              color: Colors.deepPurple,
              image: DecorationImage(
                image: NetworkImage("https://images.unsplash.com/photo-1579546929518-9e396f3cc809"),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(Colors.black45, BlendMode.darken),
              ),
            ),
            accountName: Text("TodayVacancy", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            accountEmail: Text("todayvacancy.in"),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.public, size: 40, color: Colors.deepPurple),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home, color: Colors.deepPurple),
            title: const Text('Home'),
            onTap: () {
              Navigator.pop(context); 
              onTabChange(0); 
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications, color: Colors.orange),
            title: const Text('Notifications'),
            onTap: () {
              Navigator.pop(context); 
              onTabChange(1); 
            },
          ),
          ListTile(
            leading: const Icon(Icons.favorite, color: Colors.pinkAccent),
            title: const Text('Liked Pages'),
            onTap: () {
              Navigator.pop(context);
              onTabChange(2);
            },
          ),
          ListTile(
            leading: const Icon(Icons.download, color: Colors.green),
            title: const Text('Offline Downloads'),
            onTap: () {
              Navigator.pop(context);
              onTabChange(3);
            },
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 1. WEBVIEW TAB (HOME)
// ==========================================
class WebViewTab extends StatefulWidget {
  final String url;
  final bool isOffline;
  final String? offlineHtmlContent;
  final VoidCallback? onGoToDownloads; 
  final Function(int)? onTabChange;

  const WebViewTab({
    super.key, 
    required this.url, 
    required this.isOffline, 
    this.offlineHtmlContent,
    this.onGoToDownloads,
    this.onTabChange,
  });

  @override
  State<WebViewTab> createState() => WebViewTabState();
}

class WebViewTabState extends State<WebViewTab> {
  late final WebViewController _controller;
  bool _isLoading = true;
  double _progress = 0;
  bool _hasInternet = true;

  bool _isLiked = false;
  bool _isDownloaded = false;

  final List<String> allowedInternalDomains = [
    'todayvacancy.in',
    'www.todayvacancy.in'
  ];

  @override
  void initState() {
    super.initState();
    _checkInternetConnection();
    _setupWebView();
  }

  @override
  void didUpdateWidget(WebViewTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url && !widget.isOffline) {
      _controller.loadRequest(Uri.parse(widget.url));
      _checkPageStatus(widget.url); 
    }
  }

  void loadCustomUrl(String newUrl) {
    if (!widget.isOffline) {
      _controller.loadRequest(Uri.parse(newUrl));
      _checkPageStatus(newUrl);
    }
  }

  Future<bool> canGoBack() => _controller.canGoBack();
  Future<void> goBack() => _controller.goBack();

  Future<void> _checkPageStatus(String currentUrl) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> likedList = prefs.getStringList('liked_data') ?? [];
    bool foundLike = likedList.any((e) => jsonDecode(e)['url'] == currentUrl);
    List<String> downList = prefs.getStringList('download_data') ?? [];
    bool foundDown = downList.any((e) => jsonDecode(e)['url'] == currentUrl);

    if (mounted) {
      setState(() {
        _isLiked = foundLike;
        _isDownloaded = foundDown;
      });
    }
  }

  Future<void> _checkInternetConnection() async {
    try {
      final List<ConnectivityResult> connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.isEmpty || connectivityResult.contains(ConnectivityResult.none)) {
        setState(() => _hasInternet = false);
      } else {
        setState(() => _hasInternet = true);
      }
    } catch (e) {
      setState(() => _hasInternet = true);
    }
  }

  void _setupWebView() {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final WebViewController controller = WebViewController.fromPlatformCreationParams(params);

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent("Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36")
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            setState(() { _progress = progress / 100; });
          },
          onPageStarted: (String url) {
            setState(() { _isLoading = true; });
          },
          onPageFinished: (String url) async {
            setState(() { _isLoading = false; });
            final currentUrl = await _controller.currentUrl();
            if (currentUrl != null) {
              _checkPageStatus(currentUrl); 
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (error.errorCode == -2 || error.errorCode == -6 || error.errorCode == -8) {
              if (mounted) {
                setState(() => _hasInternet = false);
              }
            }
          },
          onNavigationRequest: (NavigationRequest request) async {
            final urlString = request.url.toLowerCase();
            final uri = Uri.parse(request.url);

            if (urlString.endsWith('.pdf') || urlString.endsWith('.zip') || urlString.endsWith('.doc')) {
               _downloadFileOrPage(request.url, isDirectFileLink: true);
               return NavigationDecision.prevent;
            }

            // ==========================================
            // ADSENSE FIX: 
            // Allow iframes (Ad networks) internally
            // ==========================================
            if (!request.isMainFrame || 
                urlString.contains('googleads') || 
                urlString.contains('doubleclick') || 
                urlString.contains('googlesyndication')) {
              return NavigationDecision.navigate;
            }

            bool isInternalAppHost = allowedInternalDomains.any((domain) => uri.host.contains(domain));

            if (uri.scheme == 'http' || uri.scheme == 'https') {
              if (isInternalAppHost) {
                return NavigationDecision.navigate; 
              } else {
                try {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (e) { debugPrint("Could not launch $uri"); }
                return NavigationDecision.prevent; 
              }
            } else {
              try {
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              } catch (e) { debugPrint("Could not launch $uri"); }
              return NavigationDecision.prevent;
            }
          },
        ),
      );

    _controller = controller;

    if (widget.isOffline && widget.offlineHtmlContent != null) {
      _controller.loadHtmlString(widget.offlineHtmlContent!);
    } else {
      _controller.loadRequest(Uri.parse(widget.url));
    }
  }

  Future<void> _likeCurrentPage() async {
    final currentUrl = await _controller.currentUrl();
    final title = await _controller.getTitle() ?? "Saved Page";
    
    if (currentUrl != null && !currentUrl.startsWith('data:')) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> likedPagesList = prefs.getStringList('liked_data') ?? [];
      
      Map<String, String> pageData = {'url': currentUrl, 'title': title};
      String jsonData = jsonEncode(pageData);
      
      if (!likedPagesList.contains(jsonData)) {
        likedPagesList.add(jsonData);
        await prefs.setStringList('liked_data', likedPagesList);
        setState(() => _isLiked = true); 
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Page Liked Successfully! ❤️"), backgroundColor: Colors.green)
        );
      } else {
        likedPagesList.removeWhere((item) => jsonDecode(item)['url'] == currentUrl);
        await prefs.setStringList('liked_data', likedPagesList);
        setState(() => _isLiked = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Like Removed!"))
        );
      }
    }
  }

  Future<void> _downloadFileOrPage(String specificUrl, {bool isDirectFileLink = false}) async {
    final targetUrl = isDirectFileLink ? specificUrl : await _controller.currentUrl();
    final title = isDirectFileLink ? targetUrl!.split('/').last : (await _controller.getTitle() ?? "Downloaded Item");

    if (targetUrl != null && !targetUrl.startsWith('data:')) {
      bool isFile = targetUrl.toLowerCase().endsWith('.pdf') || 
                    targetUrl.toLowerCase().endsWith('.zip') || 
                    targetUrl.toLowerCase().endsWith('.doc') || 
                    targetUrl.toLowerCase().endsWith('.docx');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isFile ? "Downloading File... ⏳" : "Downloading Webpage... ⏳"))
      );
      
      try {
        final response = await http.get(Uri.parse(targetUrl)).timeout(const Duration(seconds: 15));
        
        if (response.statusCode == 200) {
          SharedPreferences prefs = await SharedPreferences.getInstance();
          List<String> downloadedList = prefs.getStringList('download_data') ?? [];
          Map<String, String> itemData;

          if (isFile) {
            final dir = await getApplicationDocumentsDirectory();
            String cleanFileName = targetUrl.split('/').last.split('?').first; 
            File file = File('${dir.path}/$cleanFileName');
            await file.writeAsBytes(response.bodyBytes);

            itemData = {
              'url': targetUrl, 
              'title': cleanFileName,
              'type': 'file',
              'localPath': file.path
            };
          } else {
            String htmlContent = response.body;
            htmlContent = htmlContent.replaceAll(RegExp(r'<script[^>]*adsbygoogle[^>]*>.*?</script>', caseSensitive: false, dotAll: true), '');
            htmlContent = htmlContent.replaceFirst('</head>', '<style>.adsbygoogle, .ad-container, [id^="div-gpt-ad"] { display: none !important; }</style></head>');

            itemData = {
              'url': targetUrl, 
              'title': title,
              'type': 'page',
              'html': htmlContent 
            };
          }
          
          downloadedList.add(jsonEncode(itemData));
          await prefs.setStringList('download_data', downloadedList);
          
          if (mounted) {
            if (!isDirectFileLink) setState(() => _isDownloaded = true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Download Complete! ✅"), backgroundColor: Colors.green)
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Download Failed!"), backgroundColor: Colors.red)
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOffline && !_hasInternet) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("TodayVacancy"),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                await _checkInternetConnection();
                if (_hasInternet) _controller.reload();
              },
            ),
          ],
        ),
        drawer: widget.onTabChange != null ? AppSideDrawer(onTabChange: widget.onTabChange!) : null,
        body: RefreshIndicator(
          onRefresh: () async {
            await _checkInternetConnection();
            if (_hasInternet) await _controller.reload();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(height: MediaQuery.of(context).size.height * 0.10),
              const Icon(Icons.signal_wifi_connected_no_internet_4, size: 120, color: Colors.grey),
              const SizedBox(height: 20),
              const Center(child: Text("Opps! Internet Nahi Hai", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold))),
              const SizedBox(height: 10),
              const Center(child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text("Kripya apna connection check karein ya apne offline downloads dekhein.", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.black54)),
              )),
              const SizedBox(height: 40),
              
              if (widget.onGoToDownloads != null)
                Center(
                  child: Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.deepPurple.withOpacity(0.3),
                          spreadRadius: 2,
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ]
                    ),
                    child: ElevatedButton.icon(
                      onPressed: widget.onGoToDownloads,
                      icon: const Icon(Icons.download_for_offline, size: 28),
                      label: const Text("Go to Downloads", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isOffline ? "Offline View" : "TodayVacancy"),
        actions: [
          if (!widget.isOffline) ...[
            IconButton(
              icon: const Icon(Icons.refresh), 
              onPressed: () {
                _checkInternetConnection();
                _controller.reload();
              }
            ),
          ]
        ],
      ),
      drawer: widget.onTabChange != null ? AppSideDrawer(onTabChange: widget.onTabChange!) : null,
      body: RefreshIndicator(
        color: Colors.deepPurple,
        backgroundColor: Colors.white,
        strokeWidth: 3.0,
        onRefresh: () async {
          await _checkInternetConnection();
          if (_hasInternet && !widget.isOffline) {
            await _controller.reload();
          }
        },
        child: Column(
          children: [
            if (_isLoading && !widget.isOffline) 
              LinearProgressIndicator(value: _progress, color: Colors.deepPurple),
            Expanded(child: WebViewWidget(controller: _controller)),
          ],
        ),
      ),
      floatingActionButton: !widget.isOffline ? Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "likeBtn",
            onPressed: _likeCurrentPage,
            backgroundColor: _isLiked ? Colors.pinkAccent : Colors.white,
            elevation: _isLiked ? 6 : 2,
            child: Icon(
              _isLiked ? Icons.favorite : Icons.favorite_border, 
              color: _isLiked ? Colors.white : Colors.pinkAccent
            ),
          ),
          const SizedBox(height: 15),
          FloatingActionButton(
            heroTag: "downloadBtn",
            onPressed: () async {
              String? curUrl = await _controller.currentUrl();
              if(curUrl != null) _downloadFileOrPage(curUrl);
            },
            backgroundColor: _isDownloaded ? Colors.green : Colors.white,
            elevation: _isDownloaded ? 6 : 2,
            child: Icon(
              _isDownloaded ? Icons.download_done : Icons.download, 
              color: _isDownloaded ? Colors.white : Colors.green
            ),
          ),
        ],
      ) : null,
    );
  }
}

// ==========================================
// PDF VIEWER SCREEN (App ke andar PDF kholne ke liye)
// ==========================================
class AppPDFViewer extends StatelessWidget {
  final String filePath;
  final String fileName;

  const AppPDFViewer({super.key, required this.filePath, required this.fileName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(fileName, maxLines: 1),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: PDFView(
        filePath: filePath,
        enableSwipe: true,
        swipeHorizontal: false,
        autoSpacing: false,
        pageFling: false,
      ),
    );
  }
}

// ==========================================
// 2. LIKED TAB SCREEN
// ==========================================
class LikedTab extends StatefulWidget {
  final int refreshToken; 
  final Function(int)? onTabChange;
  
  const LikedTab({super.key, required this.refreshToken, this.onTabChange});

  @override
  State<LikedTab> createState() => _LikedTabState();
}

class _LikedTabState extends State<LikedTab> {
  List<Map<String, dynamic>> _likedPages = [];

  @override
  void initState() {
    super.initState();
    _loadLikedData();
  }

  @override
  void didUpdateWidget(LikedTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _loadLikedData();
  }

  Future<void> _loadLikedData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> savedStrings = prefs.getStringList('liked_data') ?? [];
    setState(() {
      _likedPages = savedStrings.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
    });
  }

  Future<void> _removeLike(int index) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> savedStrings = prefs.getStringList('liked_data') ?? [];
    savedStrings.removeAt(index);
    await prefs.setStringList('liked_data', savedStrings);
    _loadLikedData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Liked Pages ❤️")),
      drawer: widget.onTabChange != null ? AppSideDrawer(onTabChange: widget.onTabChange!) : null,
      body: _likedPages.isEmpty
          ? const Center(child: Text("Abhi tak koi page like nahi kiya gaya hai."))
          : ListView.builder(
              itemCount: _likedPages.length,
              itemBuilder: (context, index) {
                final page = _likedPages[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    leading: const CircleAvatar(backgroundColor: Colors.pinkAccent, child: Icon(Icons.public, color: Colors.white)),
                    title: Text(page['title'] ?? "No Title", maxLines: 1),
                    subtitle: Text(page['url'] ?? "", maxLines: 1),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _removeLike(index),
                    ),
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => WebViewTab(url: page['url'], isOffline: false)));
                    },
                  ),
                );
              },
            ),
    );
  }
}

// ==========================================
// 3. DOWNLOADED TAB SCREEN (OFFLINE)
// ==========================================
class DownloadedTab extends StatefulWidget {
  final int refreshToken; 
  final Function(int)? onTabChange;

  const DownloadedTab({super.key, required this.refreshToken, this.onTabChange});

  @override
  State<DownloadedTab> createState() => _DownloadedTabState();
}

class _DownloadedTabState extends State<DownloadedTab> {
  List<Map<String, dynamic>> _downloadedItems = [];
  String _currentFilter = 'All'; 

  @override
  void initState() {
    super.initState();
    _loadDownloadedData();
  }

  @override
  void didUpdateWidget(DownloadedTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _loadDownloadedData();
  }

  Future<void> _loadDownloadedData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> savedStrings = prefs.getStringList('download_data') ?? [];
    setState(() {
      _downloadedItems = savedStrings.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
    });
  }

  Future<void> _removeDownload(int index, Map<String, dynamic> item) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> savedStrings = prefs.getStringList('download_data') ?? [];
    
    savedStrings.removeWhere((e) => jsonDecode(e)['url'] == item['url']);
    await prefs.setStringList('download_data', savedStrings);
    
    if (item['type'] == 'file' && item['localPath'] != null) {
      try {
        final file = File(item['localPath']);
        if (await file.exists()) await file.delete();
      } catch(e) { debugPrint("File delete error: $e"); }
    }

    _loadDownloadedData();
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> filteredList = _downloadedItems;
    if (_currentFilter == 'Pages') {
      filteredList = _downloadedItems.where((item) => item['type'] == 'page' || item['type'] == null).toList();
    } else if (_currentFilter == 'Files') {
      filteredList = _downloadedItems.where((item) => item['type'] == 'file').toList();
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Offline Downloads ⬇️")),
      drawer: widget.onTabChange != null ? AppSideDrawer(onTabChange: widget.onTabChange!) : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'All', label: Text('All')),
                ButtonSegment(value: 'Pages', label: Text('Web Pages')),
                ButtonSegment(value: 'Files', label: Text('Files (PDF)')),
              ],
              selected: {_currentFilter},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() => _currentFilter = newSelection.first);
              },
            ),
          ),
          
          Expanded(
            child: filteredList.isEmpty
                ? const Center(child: Text("Is category mein koi download nahi hai."))
                : ListView.builder(
                    itemCount: filteredList.length,
                    itemBuilder: (context, index) {
                      final item = filteredList[index];
                      bool isFile = item['type'] == 'file';

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isFile ? Colors.orange : Colors.green, 
                            child: Icon(isFile ? Icons.picture_as_pdf : Icons.offline_pin, color: Colors.white)
                          ),
                          title: Text(item['title'] ?? "Offline Item", maxLines: 1),
                          subtitle: Text(isFile ? "PDF/File Document" : "Available offline"),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _removeDownload(index, item),
                          ),
                          onTap: () async {
                            if (isFile) {
                              if (item['localPath'] != null && item['localPath'].toString().endsWith('.pdf')) {
                                // PDF Ab app ke andar hi khulegi!
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => AppPDFViewer(
                                      filePath: item['localPath'],
                                      fileName: item['title'] ?? "Document"
                                    )
                                  ),
                                );
                              } else if (item['localPath'] != null) {
                                // ZIP ya dusri file ke liye purana system
                                await OpenFilex.open(item['localPath']);
                              }
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => WebViewTab(
                                    url: item['url'], 
                                    isOffline: true,
                                    offlineHtmlContent: item['html'], 
                                  )
                                ),
                              );
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}