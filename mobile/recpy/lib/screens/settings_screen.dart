import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:recpy/services/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  final _listenPortController = TextEditingController();
  final _downloadPathController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final ip = await StorageService.getReceiverIp();
    final port = await StorageService.getReceiverPort();
    final listenPort = await StorageService.getListenPort();
    final downloadPath = await StorageService.getDownloadPath();

    setState(() {
      _ipController.text = ip;
      _portController.text = port.toString();
      _listenPortController.text = listenPort.toString();
      _downloadPathController.text = downloadPath;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text) ?? 12345;
    final listenPort = int.tryParse(_listenPortController.text) ?? 12345;
    final downloadPath = _downloadPathController.text.trim();

    await StorageService.setReceiverIp(ip);
    await StorageService.setReceiverPort(port);
    await StorageService.setListenPort(listenPort);
    if (downloadPath.isNotEmpty) {
      await StorageService.setDownloadPath(downloadPath);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.greenAccent),
              SizedBox(width: 8),
              Text('Settings saved successfully'),
            ],
          ),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _pickDirectory() async {
    final String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Download Folder',
    );
    if (selectedDirectory != null) {
      setState(() {
        _downloadPathController.text = selectedDirectory;
      });
    }
  }

  void _resetDownloadPath() {
    setState(() {
      _downloadPathController.text = StorageService.defaultDownloadPath;
    });
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _listenPortController.dispose();
    _downloadPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.indigoAccent),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configuration',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Configure the network details to connect and transfer data with your PC CLI.',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
            const SizedBox(height: 30),

            // Glassmorphic Card — Sender Settings
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sender Settings',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.indigoAccent,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Target IP Address field
                  TextFormField(
                    controller: _ipController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Receiver IP Address (PC)',
                      labelStyle: const TextStyle(color: Colors.grey),
                      prefixIcon: const Icon(Icons.computer, color: Colors.grey),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.indigoAccent),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.redAccent),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.redAccent),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'IP Address cannot be empty';
                      }
                      // Basic IP validation
                      final regExp = RegExp(
                        r'^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$',
                      );
                      if (!regExp.hasMatch(value.trim()) && value.trim() != 'localhost') {
                        return 'Enter a valid IP address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // Target Port field
                  TextFormField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Receiver Port',
                      labelStyle: const TextStyle(color: Colors.grey),
                      prefixIcon: const Icon(Icons.settings_ethernet, color: Colors.grey),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.indigoAccent),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Port cannot be empty';
                      }
                      final port = int.tryParse(value);
                      if (port == null || port < 1024 || port > 65535) {
                        return 'Port must be between 1024 and 65535';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),

            // Receiver listener card
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Receiver Settings',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.blueAccent,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Listening port
                  TextFormField(
                    controller: _listenPortController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Local Listening Port',
                      labelStyle: const TextStyle(color: Colors.grey),
                      prefixIcon: const Icon(Icons.hearing, color: Colors.grey),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.blueAccent),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Port cannot be empty';
                      }
                      final port = int.tryParse(value);
                      if (port == null || port < 1024 || port > 65535) {
                        return 'Port must be between 1024 and 65535';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),

            // ── Storage card ─────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Card header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.tealAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.folder_open_rounded,
                          color: Colors.tealAccent,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Storage Settings',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.tealAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose where received files will be saved on this device.',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                  const SizedBox(height: 20),

                  // Download path field
                  TextFormField(
                    controller: _downloadPathController,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 2,
                    minLines: 1,
                    decoration: InputDecoration(
                      labelText: 'Download Folder Path',
                      labelStyle: const TextStyle(color: Colors.grey),
                      hintText: StorageService.defaultDownloadPath,
                      hintStyle: TextStyle(color: Colors.grey[700], fontSize: 12),
                      prefixIcon: const Icon(Icons.folder_rounded, color: Colors.grey),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.tealAccent),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.redAccent),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.redAccent),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Download path cannot be empty';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Action buttons row
                  Row(
                    children: [
                      // Browse button
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickDirectory,
                          icon: const Icon(Icons.folder_open, size: 16),
                          label: const Text('Browse', style: TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.tealAccent,
                            side: BorderSide(color: Colors.tealAccent.withOpacity(0.4)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Reset to default button
                      OutlinedButton.icon(
                        onPressed: _resetDownloadPath,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Reset', style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey[400],
                          side: BorderSide(color: Colors.white.withOpacity(0.15)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ],
                  ),

                  // Current path hint
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 13, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Default: ${StorageService.defaultDownloadPath}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 35),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _saveSettings,
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
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF3B82F6)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Container(
                    alignment: Alignment.center,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.save, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Save Settings',
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
        ),
      ),
    );
  }
}
