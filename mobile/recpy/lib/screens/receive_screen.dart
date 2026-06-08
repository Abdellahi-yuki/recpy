import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ReceivedItem {
  final String id;
  final String senderIp;
  final String type; // 'text' or 'file'
  final String? textContent;
  final String? filename;
  final String? savedPath;
  final DateTime timestamp;

  ReceivedItem({
    required this.id,
    required this.senderIp,
    required this.type,
    this.textContent,
    this.filename,
    this.savedPath,
    required this.timestamp,
  });
}

class ReceiveScreen extends StatelessWidget {
  final bool isServerRunning;
  final String serverStatus;
  final List<String> localIps;
  final List<ReceivedItem> receivedItems;
  final String activeTransferInfo;
  final double activeTransferProgress;
  final ValueChanged<bool> onToggleServer;
  final VoidCallback onClearHistory;

  const ReceiveScreen({
    super.key,
    required this.isServerRunning,
    required this.serverStatus,
    required this.localIps,
    required this.receivedItems,
    required this.activeTransferInfo,
    required this.activeTransferProgress,
    required this.onToggleServer,
    required this.onClearHistory,
  });

  void _copyToClipboard(BuildContext context, String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.copy, color: Colors.blueAccent),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
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
            'Receive',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Listen for incoming texts and files from your PC CLI.',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
          const SizedBox(height: 20),

          // Server Control Card
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isServerRunning
                    ? Colors.greenAccent.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isServerRunning ? Colors.greenAccent : Colors.grey,
                                boxShadow: isServerRunning
                                    ? [
                                        BoxShadow(
                                          color: Colors.greenAccent.withValues(alpha: 0.6),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        )
                                      ]
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isServerRunning ? 'Server Active' : 'Server Inactive',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          serverStatus,
                          style: TextStyle(
                            color: isServerRunning ? Colors.greenAccent[100] : Colors.grey[400],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    Switch(
                      value: isServerRunning,
                      onChanged: onToggleServer,
                      activeThumbColor: Colors.greenAccent,
                      activeTrackColor: Colors.greenAccent.withValues(alpha: 0.3),
                    ),
                  ],
                ),
                
                if (isServerRunning) ...[
                  const Divider(color: Colors.white24, height: 25),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Your Device IP Addresses:',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: localIps.map((ip) {
                      return GestureDetector(
                        onTap: () => _copyToClipboard(context, ip, "IP Address copied!"),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.copy, size: 12, color: Colors.grey),
                              const SizedBox(width: 6),
                              Text(
                                ip,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 13,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Active Transfer Display
          if (activeTransferInfo.isNotEmpty) ...[
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.2)),
              ),
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.greenAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          activeTransferInfo,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: activeTransferProgress,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // History Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Received Items Log',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              if (receivedItems.isNotEmpty)
                TextButton(
                  onPressed: onClearHistory,
                  child: const Text(
                    'Clear Log',
                    style: TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // History List
          Expanded(
            child: receivedItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 48,
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No items received yet',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: receivedItems.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = receivedItems[index];
                      final isText = item.type == 'text';

                      return Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        padding: const EdgeInsets.all(15),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isText ? Icons.text_fields : Icons.insert_drive_file,
                                      color: isText ? Colors.blueAccent : Colors.greenAccent,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      isText ? 'Text Snippet' : 'Received File',
                                      style: TextStyle(
                                        color: isText ? Colors.blueAccent[100] : Colors.greenAccent[100],
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  _formatTime(item.timestamp),
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Content
                            if (isText) ...[
                              SelectableText(
                                item.textContent ?? "",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Text(
                                    'From: ${item.senderIp}',
                                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                                  ),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: () => _copyToClipboard(
                                      context,
                                      item.textContent ?? "",
                                      "Copied message text!",
                                    ),
                                    icon: const Icon(Icons.copy, size: 14),
                                    label: const Text('Copy', style: TextStyle(fontSize: 12)),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              Text(
                                item.filename ?? "Unknown file",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                'Saved to: ${item.savedPath}',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Text(
                                    'From: ${item.senderIp}',
                                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                                  ),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: () => _copyToClipboard(
                                      context,
                                      item.savedPath ?? "",
                                      "File path copied!",
                                    ),
                                    icon: const Icon(Icons.copy, size: 14),
                                    label: const Text('Copy Path', style: TextStyle(fontSize: 12)),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
