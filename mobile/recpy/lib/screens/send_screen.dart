import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:recpy/services/network_service.dart';
import 'package:recpy/services/storage_service.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  int _activeTab = 0; // 0 = Text, 1 = Files
  
  // Text Mode state
  final _textController = TextEditingController();
  
  // Files Mode state
  final List<File> _selectedFiles = [];
  
  // Transmission Status
  bool _isSending = false;
  String _sendingStatus = "";
  double _sendProgress = 0.0;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
      );
      
      if (result != null && result.paths.isNotEmpty) {
        setState(() {
          _selectedFiles.addAll(
            result.paths.where((p) => p != null).map((p) => File(p!)),
          );
        });
      }
    } catch (e) {
      _showSnackbar("Failed to pick files: $e", Colors.redAccent);
    }
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  void _clearFiles() {
    setState(() {
      _selectedFiles.clear();
    });
  }

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

  /// Maps raw socket/OS exceptions to human-readable messages.
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

    setState(() {
      _isSending = true;
      _sendingStatus = "Connecting...";
      _sendProgress = 0.0;
    });

    try {
      final ip = await StorageService.getReceiverIp();
      final port = await StorageService.getReceiverPort();
      
      setState(() {
        _sendingStatus = "Sending to $ip:$port...";
      });

      await NetworkService.sendText(
        ip: ip,
        port: port,
        text: text,
        onProgress: (progress) {
          setState(() {
            _sendProgress = progress;
            if (progress >= 1.0) {
              _sendingStatus = "Text sent successfully!";
            }
          });
        },
      );
      
      _textController.clear();
      _showSnackbar("Text sent successfully!", Colors.greenAccent);
    } catch (e) {
      final msg = _friendlyError(e);
      _showSnackbar(msg, Colors.redAccent);
      setState(() {
        _sendingStatus = msg;
      });
    } finally {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _isSending = false;
            _sendingStatus = "";
            _sendProgress = 0.0;
          });
        }
      });
    }
  }

  Future<void> _handleSendFiles() async {
    if (_selectedFiles.isEmpty) {
      _showSnackbar("Please select at least one file to send", Colors.orangeAccent);
      return;
    }

    setState(() {
      _isSending = true;
      _sendingStatus = "Connecting...";
      _sendProgress = 0.0;
    });

    try {
      final ip = await StorageService.getReceiverIp();
      final port = await StorageService.getReceiverPort();

      setState(() {
        _sendingStatus = "Sending ${_selectedFiles.length} files to $ip:$port...";
      });

      await NetworkService.sendFiles(
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

      setState(() {
        _sendingStatus = "All files sent successfully!";
        _sendProgress = 1.0;
      });

      _clearFiles();
      _showSnackbar("All files sent successfully!", Colors.greenAccent);
    } catch (e) {
      final msg = _friendlyError(e);
      _showSnackbar(msg, Colors.redAccent);
      setState(() {
        _sendingStatus = msg;
      });
    } finally {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _isSending = false;
            _sendingStatus = "";
            _sendProgress = 0.0;
          });
        }
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
          const Text(
            'Transmit',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Send text snippets or files directly to the receiver.',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
          const SizedBox(height: 25),

          // Custom Pill Selector
          Container(
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withOpacity(0.5),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (!_isSending) setState(() => _activeTab = 0);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: _activeTab == 0
                            ? const LinearGradient(
                                colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                              )
                            : null,
                        borderRadius: BorderRadius.circular(21),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Text Message',
                        style: TextStyle(
                          color: _activeTab == 0 ? Colors.white : Colors.grey[400],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (!_isSending) setState(() => _activeTab = 1);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: _activeTab == 1
                            ? const LinearGradient(
                                colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                              )
                            : null,
                        borderRadius: BorderRadius.circular(21),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Files',
                        style: TextStyle(
                          color: _activeTab == 1 ? Colors.white : Colors.grey[400],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 25),

          // Sending Status Display
          if (_isSending) ...[
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withOpacity(0.8),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.indigoAccent.withOpacity(0.2)),
              ),
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.indigoAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _sendingStatus,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: _sendProgress,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.indigoAccent),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Active Panel
          Expanded(
            child: _activeTab == 0 ? _buildTextPanel() : _buildFilesPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildTextPanel() {
    return Column(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withOpacity(0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            padding: const EdgeInsets.all(15),
            child: TextField(
              controller: _textController,
              maxLines: null,
              enabled: !_isSending,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: const InputDecoration(
                hintText: 'Type or paste content to send...',
                hintStyle: TextStyle(color: Colors.grey),
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 55,
          child: ElevatedButton(
            onPressed: _isSending ? null : _handleSendText,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: Ink(
              decoration: BoxDecoration(
                gradient: _isSending
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                      ),
                color: _isSending ? Colors.grey[800] : null,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Container(
                alignment: Alignment.center,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.send, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Send Text',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildFilesPanel() {
    return Column(
      children: [
        // File Pick Area
        GestureDetector(
          onTap: _isSending ? null : _pickFiles,
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withOpacity(0.4),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.indigoAccent.withOpacity(0.3),
                style: BorderStyle.solid,
                width: 1.5,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    size: 40,
                    color: Colors.indigoAccent.withOpacity(0.8),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap to select files',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select one or multiple files',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 15),

        // Files List Header
        if (_selectedFiles.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Selected Files (${_selectedFiles.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: _isSending ? null : _clearFiles,
                child: const Text(
                  'Clear All',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
        ],

        // Files List
        Expanded(
          child: _selectedFiles.isEmpty
              ? Center(
                  child: Text(
                    'No files selected yet',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                )
              : Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: _selectedFiles.length,
                    separatorBuilder: (context, index) => Divider(
                      color: Colors.white.withOpacity(0.05),
                      height: 1,
                    ),
                    itemBuilder: (context, index) {
                      final file = _selectedFiles[index];
                      final name = file.path.split('/').last;
                      final size = _getFileSizeString(file.lengthSync());

                      return ListTile(
                        leading: const Icon(
                          Icons.insert_drive_file,
                          color: Colors.indigoAccent,
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          size,
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: _isSending ? null : () => _removeFile(index),
                        ),
                      );
                    },
                  ),
                ),
        ),
        const SizedBox(height: 20),

        // Send Files button
        SizedBox(
          width: double.infinity,
          height: 55,
          child: ElevatedButton(
            onPressed: _isSending || _selectedFiles.isEmpty ? null : _handleSendFiles,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: Ink(
              decoration: BoxDecoration(
                gradient: _isSending || _selectedFiles.isEmpty
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                      ),
                color: _isSending || _selectedFiles.isEmpty ? Colors.grey[800] : null,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Container(
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.send, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      _isSending ? 'Sending...' : 'Send Files',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
