import 'package:flutter/material.dart';
import 'package:recpy/screens/send_screen.dart';
import 'package:recpy/screens/receive_screen.dart';
import 'package:recpy/screens/settings_screen.dart';
import 'package:recpy/services/network_service.dart';
import 'package:recpy/services/storage_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'recpy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _currentIndex = 0;
  final NetworkService _networkService = NetworkService();
  
  bool _isServerRunning = false;
  String _serverStatus = "Stopped";
  List<String> _localIps = [];
  final List<ReceivedItem> _receivedItems = [];
  
  String _activeTransferInfo = "";
  double _activeTransferProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _loadLocalIps();
  }

  @override
  void dispose() {
    _networkService.stopServer((status) {});
    super.dispose();
  }

  Future<void> _loadLocalIps() async {
    final ips = await NetworkService.getLocalIps();
    setState(() {
      _localIps = ips;
    });
  }

  Future<void> _toggleServer(bool start) async {
    if (start) {
      final port = await StorageService.getListenPort();
      await _networkService.startServer(
        port: port,
        onTextReceived: (clientIp, text) {
          setState(() {
            _receivedItems.insert(
              0,
              ReceivedItem(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                senderIp: clientIp,
                type: 'text',
                textContent: text,
                timestamp: DateTime.now(),
              ),
            );
            _activeTransferInfo = "";
            _activeTransferProgress = 0.0;
          });
        },
        onFileReceived: (clientIp, filename, savedPath) {
          setState(() {
            _receivedItems.insert(
              0,
              ReceivedItem(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                senderIp: clientIp,
                type: 'file',
                filename: filename,
                savedPath: savedPath,
                timestamp: DateTime.now(),
              ),
            );
            _activeTransferInfo = "";
            _activeTransferProgress = 0.0;
          });
        },
        onTransferProgress: (clientIp, info, progress) {
          setState(() {
            _activeTransferInfo = info;
            _activeTransferProgress = progress;
          });
        },
        onStatusChanged: (status) {
          setState(() {
            _serverStatus = status;
            _isServerRunning = _networkService.isListening;
          });
        },
        onError: (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(error),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        },
      );
    } else {
      _networkService.stopServer((status) {
        setState(() {
          _serverStatus = status;
          _isServerRunning = false;
          _activeTransferInfo = "";
          _activeTransferProgress = 0.0;
        });
      });
    }
  }

  void _clearHistory() {
    setState(() {
      _receivedItems.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      const SendScreen(),
      ReceiveScreen(
        isServerRunning: _isServerRunning,
        serverStatus: _serverStatus,
        localIps: _localIps,
        receivedItems: _receivedItems,
        activeTransferInfo: _activeTransferInfo,
        activeTransferProgress: _activeTransferProgress,
        onToggleServer: _toggleServer,
        onClearHistory: _clearHistory,
      ),
      const SettingsScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF3B82F6)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.swap_horizontal_circle_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'recpy',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          if (_isServerRunning)
            Container(
              margin: const EdgeInsets.only(right: 15),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.wifi_tethering, size: 12, color: Colors.greenAccent),
                  SizedBox(width: 5),
                  Text(
                    'Listening',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: screens,
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          border: Border(
            top: BorderSide(
              color: Colors.white.withOpacity(0.05),
              width: 1,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFF6366F1),
          unselectedItemColor: Colors.grey[500],
          selectedFontSize: 12,
          unselectedFontSize: 12,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.send_rounded),
              activeIcon: Icon(Icons.send_rounded, color: Color(0xFF6366F1)),
              label: 'Send',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.download_rounded),
              activeIcon: Icon(Icons.download_rounded, color: Color(0xFF6366F1)),
              label: 'Receive',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_rounded),
              activeIcon: Icon(Icons.settings_rounded, color: Color(0xFF6366F1)),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
