import 'package:flutter/material.dart';
import 'package:recpy/services/native_file_picker.dart';
import 'package:recpy/services/network_service.dart';
import 'package:recpy/services/storage_service.dart';
import 'package:recpy/services/foreground_service_manager.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  int _activeTab = 0;

  final _textController = TextEditingController();

  // NativeFile holds uri+name+size — returned instantly, no copy
  final List<NativeFile> _selectedFiles = [];
  bool _isPickingFiles = false;

  bool _isSending = false;
  String _sendingStatus = "";
  double _sendProgress = 0.0;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    if (_isPickingFiles) return;
    setState(() => _isPickingFiles = true);
    // Acquire foreground service so the send socket survives while the
    // file picker pushes the app to the background.
    await ForegroundServiceManager.acquire(
      title: 'recpy',
      text: 'Selecting files…',
    );
    try {
      final files = await NativeFilePicker.pickFiles();
      if (files != null && files.isNotEmpty) {
        setState(() => _selectedFiles.addAll(files));
      }
    } catch (e) {
      _showSnackbar('Failed to open file picker: $e', Colors.redAccent);
    } finally {
      await ForegroundServiceManager.release();
      if (mounted) setState(() => _isPickingFiles = false);
    }
  }

  void _removeFile(int index) => setState(() => _selectedFiles.removeAt(index));
  void _clearFiles() => setState(() => _selectedFiles.clear());

  void _showSnackbar(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _friendlyError(Object e) {
    final raw = e.toString().toLowerCase();
    if (raw.contains('errno = 111') || raw.contains('connection refused')) {
      return 'Connection refused — verify the receiver IP and port number.';
    }
    if (raw.contains('errno = 110') || raw.contains('timed out') || raw.contains('connection timed out')) {
      return 'Connection timed out — make sure the receiver is reachable on the same network.';
    }
    if (raw.contains('errno = 113') || raw.contains('no route to host')) {
      return 'No route to host — check that both devices are on the same Wi-Fi network.';
    }
    if (raw.contains('errno = 101') || raw.contains('network is unreachable')) {
      return 'Network unreachable — check your Wi-Fi connection.';
    }
    if (raw.contains('errno = 104') || raw.contains('connection reset')) {
      return 'Connection was reset by the receiver. Try again.';
    }
    if (raw.contains('failed host lookup') || raw.contains('nodename nor servname')) {
      return 'Could not resolve host — check the IP address in Settings.';
    }
    return 'Send failed: $e';
  }

  Future<void> _handleSendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showSnackbar("Please enter some text to send", Colors.orangeAccent);
      return;
    }

    setState(() { _isSending = true; _sendingStatus = "Connecting..."; _sendProgress = 0.0; });

    try {
      await WakelockPlus.enable();
      await ForegroundServiceManager.acquire(
        title: 'recpy is sending',
        text: 'Sending text…',
      );
      final ip = await StorageService.getReceiverIp();
      final port = await StorageService.getReceiverPort();
      setState(() => _sendingStatus = "Sending to $ip:$port...");

      await NetworkService.sendText(
        ip: ip, port: port, text: text,
        onProgress: (progress) {
          setState(() {
            _sendProgress = progress;
            if (progress >= 1.0) _sendingStatus = "Text sent successfully!";
          });
        },
      );
      _textController.clear();
      _showSnackbar("Text sent successfully!", Colors.greenAccent);
    } catch (e) {
      final msg = _friendlyError(e);
      _showSnackbar(msg, Colors.redAccent);
      setState(() => _sendingStatus = msg);
    } finally {
      await ForegroundServiceManager.release();
      await WakelockPlus.disable();
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() { _isSending = false; _sendingStatus = ""; _sendProgress = 0.0; });
      });
    }
  }

  Future<void> _handleSendFiles() async {
    if (_selectedFiles.isEmpty) {
      _showSnackbar("Please select at least one file to send", Colors.orangeAccent);
      return;
    }

    setState(() { _isSending = true; _sendingStatus = "Connecting..."; _sendProgress = 0.0; });

    try {
      await WakelockPlus.enable();
      await ForegroundServiceManager.acquire(
        title: 'recpy is sending',
        text: 'Sending files…',
      );
      final ip = await StorageService.getReceiverIp();
      final port = await StorageService.getReceiverPort();

      await NetworkService.sendFilesNative(
        ip: ip,
        port: port,
        files: _selectedFiles,
        onProgress: (filename, progress) {
          setState(() {
            _sendingStatus = "Sending $filename...";
            _sendProgress = progress;
          });
        },
      );

      setState(() { _sendingStatus = "All files sent successfully!"; _sendProgress = 1.0; });
      _clearFiles();
      _showSnackbar("All files sent successfully!", Colors.greenAccent);
    } catch (e) {
      final msg = _friendlyError(e);
      _showSnackbar(msg, Colors.redAccent);
      setState(() => _sendingStatus = msg);
    } finally {
      await ForegroundServiceManager.release();
      await WakelockPlus.disable();
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() { _isSending = false; _sendingStatus = ""; _sendProgress = 0.0; });
      });
    }
  }

  String _getFileSizeString(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          const Text('Transmit',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)),
          const SizedBox(height: 5),
          Text('Send text snippets or files directly to the receiver.',
            style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          const SizedBox(height: 25),

          // Pill tab selector
          Container(
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [0, 1].map((tab) {
                final labels = ['Text Message', 'Files'];
                final active = _activeTab == tab;
                return Expanded(
                  child: GestureDetector(
                    onTap: () { if (!_isSending) setState(() => _activeTab = tab); },
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: active ? const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF4F46E5)]) : null,
                        borderRadius: BorderRadius.circular(21),
                      ),
                      alignment: Alignment.center,
                      child: Text(labels[tab],
                        style: TextStyle(color: active ? Colors.white : Colors.grey[400], fontWeight: FontWeight.bold)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 25),

          // Sending progress card
          if (_isSending) ...[
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.indigoAccent.withValues(alpha: 0.2)),
              ),
              padding: const EdgeInsets.all(15),
              child: Column(
                children: [
                  Row(children: [
                    const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.indigoAccent)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_sendingStatus,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis)),
                  ]),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: _sendProgress,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.indigoAccent),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          Expanded(child: _activeTab == 0 ? _buildTextPanel() : _buildFilesPanel()),
        ],
      ),
    );
  }

  Widget _buildTextPanel() {
    return Column(children: [
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          padding: const EdgeInsets.all(15),
          child: TextField(
            controller: _textController, maxLines: null, enabled: !_isSending,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: const InputDecoration(
              hintText: 'Type or paste content to send...',
              hintStyle: TextStyle(color: Colors.grey), border: InputBorder.none),
          ),
        ),
      ),
      const SizedBox(height: 20),
      _buildSendButton(label: 'Send Text', onTap: _isSending ? null : _handleSendText, active: !_isSending),
      const SizedBox(height: 20),
    ]);
  }

  Widget _buildFilesPanel() {
    return Column(children: [
      GestureDetector(
        onTap: _isPickingFiles ? null : _pickFiles,
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.indigoAccent.withValues(alpha: 0.3), width: 1.5),
          ),
          child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.cloud_upload_outlined, size: 40, color: Colors.indigoAccent.withValues(alpha: 0.8)),
            const SizedBox(height: 8),
            Text(_isPickingFiles ? 'Opening picker...' : 'Tap to select files',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Select one or multiple files', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ])),
        ),
      ),
      const SizedBox(height: 15),

      if (_selectedFiles.isNotEmpty) ...[
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Selected Files (${_selectedFiles.length})',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          TextButton(
            onPressed: _isSending ? null : _clearFiles,
            child: const Text('Clear All', style: TextStyle(color: Colors.redAccent))),
        ]),
        const SizedBox(height: 5),
      ],

      Expanded(
        child: _selectedFiles.isEmpty
            ? Center(child: Text('No files selected yet', style: TextStyle(color: Colors.grey[600])))
            : Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: ListView.separated(
                  padding: const EdgeInsets.all(10),
                  itemCount: _selectedFiles.length,
                  separatorBuilder: (context, index) => Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
                  itemBuilder: (context, index) {
                    final f = _selectedFiles[index];
                    return ListTile(
                      leading: const Icon(Icons.insert_drive_file, color: Colors.indigoAccent),
                      title: Text(f.name,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(_getFileSizeString(f.size),
                        style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: _isSending ? null : () => _removeFile(index)),
                    );
                  },
                ),
              ),
      ),
      const SizedBox(height: 20),
      _buildSendButton(
        label: _isSending ? 'Sending...' : 'Send Files',
        onTap: (_isSending || _selectedFiles.isEmpty) ? null : _handleSendFiles,
        active: !_isSending && _selectedFiles.isNotEmpty,
      ),
      const SizedBox(height: 20),
    ]);
  }

  Widget _buildSendButton({required String label, required VoidCallback? onTap, required bool active}) {
    return SizedBox(
      width: double.infinity, height: 55,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
          padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
        child: Ink(
          decoration: BoxDecoration(
            gradient: active ? const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF4F46E5)]) : null,
            color: active ? null : Colors.grey[800],
            borderRadius: BorderRadius.circular(15)),
          child: Container(alignment: Alignment.center,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.send, color: Colors.white), const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ])),
        ),
      ),
    );
  }
}
