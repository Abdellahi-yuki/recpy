import 'package:flutter/material.dart';
import 'package:recpy/services/native_file_picker.dart';
import 'package:recpy/services/network_service.dart';
import 'package:recpy/services/storage_service.dart';
import 'package:recpy/services/foreground_service_manager.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

// ─── Queue item status ────────────────────────────────────────────────────────

enum QueueStatus { pending, sending, done, cancelled, failed }

class QueuedFile {
  final String id;
  final NativeFile file;
  QueueStatus status;
  double progress;
  CancelToken cancelToken;

  QueuedFile({required this.file})
      : id = '${file.uri}_${DateTime.now().microsecondsSinceEpoch}',
        status = QueueStatus.pending,
        progress = 0,
        cancelToken = CancelToken();
}

// ─── History entry ────────────────────────────────────────────────────────────

enum HistoryType { fileSent, textSent }

class HistoryEntry {
  final HistoryType type;
  final String label;      // filename or text snippet
  final DateTime time;

  const HistoryEntry({required this.type, required this.label, required this.time});
}

// ─── SendScreen ───────────────────────────────────────────────────────────────

class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  int _activeTab = 0;

  // ── Text tab ──────────────────────────────────────────────────────────────
  final _textController = TextEditingController();
  bool _isSendingText = false;

  // ── Files tab ─────────────────────────────────────────────────────────────
  final List<QueuedFile> _queue = [];
  bool _isPickingFiles = false;
  bool _queueRunning = false;  // true while the background loop is active

  // ── History ───────────────────────────────────────────────────────────────
  final List<HistoryEntry> _history = [];

  @override
  void dispose() {
    _textController.dispose();
    // Cancel any active sends on dispose
    for (final item in _queue) {
      item.cancelToken.cancel();
    }
    super.dispose();
  }

  // ── File picker ───────────────────────────────────────────────────────────

  Future<void> _pickFiles() async {
    if (_isPickingFiles) return;
    setState(() => _isPickingFiles = true);
    await ForegroundServiceManager.acquire(title: 'recpy', text: 'Selecting files…');
    try {
      final files = await NativeFilePicker.pickFiles();
      if (files != null && files.isNotEmpty) {
        setState(() {
          for (final f in files) {
            _queue.add(QueuedFile(file: f));
          }
        });
        // Auto-start the queue if it's not already running
        _startQueueIfIdle();
      }
    } catch (e) {
      _showSnackbar('Failed to open file picker: $e', Colors.redAccent);
    } finally {
      await ForegroundServiceManager.release();
      if (mounted) setState(() => _isPickingFiles = false);
    }
  }

  // ── Queue loop ────────────────────────────────────────────────────────────

  void _startQueueIfIdle() {
    if (_queueRunning) return;
    final hasPending = _queue.any((q) => q.status == QueueStatus.pending);
    if (!hasPending) return;
    _runQueue();
  }

  Future<void> _runQueue() async {
    if (_queueRunning) return;
    setState(() => _queueRunning = true);
    await WakelockPlus.enable();
    await ForegroundServiceManager.acquire(
        title: 'recpy is sending', text: 'Sending files…');

    try {
      while (true) {
        // Find next pending item
        final idx = _queue.indexWhere((q) => q.status == QueueStatus.pending);
        if (idx == -1) break; // nothing left

        final item = _queue[idx];
        item.cancelToken = CancelToken(); // fresh token for this attempt
        setState(() => item.status = QueueStatus.sending);

        final ip = await StorageService.getReceiverIp();
        final port = await StorageService.getReceiverPort();

        try {
          final completed = await NetworkService.sendSingleFileNative(
            ip: ip,
            port: port,
            file: item.file,
            cancelToken: item.cancelToken,
            onProgress: (progress) {
              if (mounted) setState(() => item.progress = progress);
            },
          );

          if (mounted) {
            setState(() {
              item.status =
                  completed ? QueueStatus.done : QueueStatus.cancelled;
              if (completed) item.progress = 1.0;
            });
            if (completed) {
              _history.insert(
                0,
                HistoryEntry(
                  type: HistoryType.fileSent,
                  label: item.file.name,
                  time: DateTime.now(),
                ),
              );
            }
          }
        } catch (e) {
          if (mounted) {
            setState(() => item.status = QueueStatus.failed);
            _showSnackbar(_friendlyError(e), Colors.redAccent);
          }
        }
      }
    } finally {
      await ForegroundServiceManager.release();
      await WakelockPlus.disable();
      if (mounted) setState(() => _queueRunning = false);
    }
  }

  // Cancel a specific item in the queue
  void _cancelItem(QueuedFile item) {
    if (item.status == QueueStatus.sending) {
      item.cancelToken.cancel();
      // The queue loop will mark it cancelled and move on
    } else if (item.status == QueueStatus.pending) {
      setState(() => item.status = QueueStatus.cancelled);
    }
  }

  // Remove finished/cancelled items from the list
  void _clearCompleted() {
    setState(() => _queue.removeWhere((q) =>
        q.status == QueueStatus.done ||
        q.status == QueueStatus.cancelled ||
        q.status == QueueStatus.failed));
  }

  // Re-queue failed items
  void _retryFailed() {
    setState(() {
      for (final item in _queue) {
        if (item.status == QueueStatus.failed) {
          item.status = QueueStatus.pending;
          item.progress = 0;
        }
      }
    });
    _startQueueIfIdle();
  }

  // ── Text send ─────────────────────────────────────────────────────────────

  Future<void> _handleSendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showSnackbar('Please enter some text to send', Colors.orangeAccent);
      return;
    }
    setState(() => _isSendingText = true);
    await WakelockPlus.enable();
    await ForegroundServiceManager.acquire(
        title: 'recpy is sending', text: 'Sending text…');
    try {
      final ip = await StorageService.getReceiverIp();
      final port = await StorageService.getReceiverPort();
      await NetworkService.sendText(
        ip: ip, port: port, text: text,
        onProgress: (_) {},
      );
      _history.insert(
        0,
        HistoryEntry(
          type: HistoryType.textSent,
          label: text.length > 80 ? '${text.substring(0, 80)}…' : text,
          time: DateTime.now(),
        ),
      );
      _textController.clear();
      _showSnackbar('Text sent successfully!', Colors.greenAccent);
    } catch (e) {
      _showSnackbar(_friendlyError(e), Colors.redAccent);
    } finally {
      await ForegroundServiceManager.release();
      await WakelockPlus.disable();
      if (mounted) setState(() => _isSendingText = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _showSnackbar(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  String _friendlyError(Object e) {
    final raw = e.toString().toLowerCase();
    if (raw.contains('errno = 111') || raw.contains('connection refused')) {
      return 'Connection refused — verify the receiver IP and port number.';
    }
    if (raw.contains('errno = 110') || raw.contains('timed out')) {
      return 'Connection timed out — make sure the receiver is reachable.';
    }
    if (raw.contains('errno = 113') || raw.contains('no route to host')) {
      return 'No route to host — check both devices are on the same Wi-Fi.';
    }
    if (raw.contains('errno = 101') || raw.contains('network is unreachable')) {
      return 'Network unreachable — check your Wi-Fi connection.';
    }
    if (raw.contains('errno = 104') || raw.contains('connection reset')) {
      return 'Connection was reset by the receiver. Try again.';
    }
    return 'Send failed: $e';
  }

  String _sizeStr(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _timeStr(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 20),
        const Text('Transmit',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5)),
        const SizedBox(height: 5),
        Text('Send text snippets or files directly to the receiver.',
            style: TextStyle(color: Colors.grey[400], fontSize: 14)),
        const SizedBox(height: 25),

        // Pill tab selector — allow switching even while sending
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
                  onTap: () => setState(() => _activeTab = tab),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: active
                          ? const LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFF4F46E5)])
                          : null,
                      borderRadius: BorderRadius.circular(21),
                    ),
                    alignment: Alignment.center,
                    child: Text(labels[tab],
                        style: TextStyle(
                            color: active ? Colors.white : Colors.grey[400],
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 25),

        Expanded(child: _activeTab == 0 ? _buildTextPanel() : _buildFilesPanel()),
      ]),
    );
  }

  // ── Text panel ────────────────────────────────────────────────────────────

  Widget _buildTextPanel() {
    final hasHistory = _history.any((h) => h.type == HistoryType.textSent);
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
            controller: _textController,
            maxLines: null,
            enabled: !_isSendingText,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: const InputDecoration(
              hintText: 'Type or paste content to send...',
              hintStyle: TextStyle(color: Colors.grey),
              border: InputBorder.none,
            ),
          ),
        ),
      ),
      const SizedBox(height: 15),
      _buildActionButton(
        label: _isSendingText ? 'Sending…' : 'Send Text',
        icon: Icons.send,
        onTap: _isSendingText ? null : _handleSendText,
        active: !_isSendingText,
      ),

      // Sent text history
      if (hasHistory) ...[
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Sent Texts',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
          TextButton(
            onPressed: () =>
                setState(() => _history.removeWhere((h) => h.type == HistoryType.textSent)),
            child: const Text('Clear', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
          ),
        ]),
        Expanded(
          child: _buildHistoryList(HistoryType.textSent),
        ),
      ],
      const SizedBox(height: 20),
    ]);
  }

  // ── Files panel ───────────────────────────────────────────────────────────

  Widget _buildFilesPanel() {
    final pendingCount = _queue.where((q) => q.status == QueueStatus.pending).length;
    final hasCompleted = _queue.any((q) =>
        q.status == QueueStatus.done ||
        q.status == QueueStatus.cancelled ||
        q.status == QueueStatus.failed);
    final hasFailed = _queue.any((q) => q.status == QueueStatus.failed);
    final hasFileHistory = _history.any((h) => h.type == HistoryType.fileSent);

    return Column(children: [
      // Pick area
      GestureDetector(
        onTap: _isPickingFiles ? null : _pickFiles,
        child: Container(
          height: 100,
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: Colors.indigoAccent.withValues(alpha: 0.3), width: 1.5),
          ),
          child: Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.cloud_upload_outlined,
                  size: 32, color: Colors.indigoAccent.withValues(alpha: 0.8)),
              const SizedBox(height: 6),
              Text(
                  _isPickingFiles ? 'Opening picker...' : 'Tap to add files to queue',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 12),

      // Queue header
      if (_queue.isNotEmpty) ...[
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(
            _queueRunning
                ? 'Sending… ($pendingCount pending)'
                : 'Queue (${_queue.length})',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          Row(children: [
            if (hasFailed)
              TextButton(
                onPressed: _retryFailed,
                style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text('Retry failed',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
              ),
            if (hasCompleted)
              TextButton(
                onPressed: _clearCompleted,
                style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text('Clear done',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ),
          ]),
        ]),
        const SizedBox(height: 5),
      ],

      // Queue list
      Flexible(
        flex: 3,
        child: _queue.isEmpty
            ? Center(
                child: Text('No files queued',
                    style: TextStyle(color: Colors.grey[600])))
            : Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: _queue.length,
                  separatorBuilder: (context, index) => Divider(
                      color: Colors.white.withValues(alpha: 0.05), height: 1),
                  itemBuilder: (context, i) => _buildQueueTile(_queue[i]),
                ),
              ),
      ),

      const SizedBox(height: 12),

      // Send button — only shown when there are pending files and queue is idle
      if (!_queueRunning && _queue.any((q) => q.status == QueueStatus.pending))
        _buildActionButton(
          label: 'Start Sending',
          icon: Icons.send,
          onTap: _runQueue,
          active: true,
        ),

      // Sent files history
      if (hasFileHistory) ...[
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Sent Files',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
          TextButton(
            onPressed: () => setState(
                () => _history.removeWhere((h) => h.type == HistoryType.fileSent)),
            style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: const Text('Clear',
                style: TextStyle(color: Colors.redAccent, fontSize: 12)),
          ),
        ]),
        Flexible(
          flex: 2,
          child: _buildHistoryList(HistoryType.fileSent),
        ),
      ],
      const SizedBox(height: 20),
    ]);
  }

  // ── Queue tile ────────────────────────────────────────────────────────────

  Widget _buildQueueTile(QueuedFile item) {
    final isSending = item.status == QueueStatus.sending;
    final isDone = item.status == QueueStatus.done;
    final isCancelled = item.status == QueueStatus.cancelled;
    final isFailed = item.status == QueueStatus.failed;

    Color statusColor;
    IconData statusIcon;
    if (isDone) {
      statusColor = Colors.greenAccent;
      statusIcon = Icons.check_circle;
    } else if (isCancelled) {
      statusColor = Colors.grey;
      statusIcon = Icons.cancel;
    } else if (isFailed) {
      statusColor = Colors.redAccent;
      statusIcon = Icons.error;
    } else if (isSending) {
      statusColor = Colors.indigoAccent;
      statusIcon = Icons.upload;
    } else {
      statusColor = Colors.grey;
      statusIcon = Icons.hourglass_empty;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Status icon / spinner
          SizedBox(
            width: 22,
            height: 22,
            child: isSending
                ? CircularProgressIndicator(
                    value: item.progress > 0 ? item.progress : null,
                    strokeWidth: 2,
                    color: Colors.indigoAccent,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                  )
                : Icon(statusIcon, size: 18, color: statusColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.file.name,
                  style: TextStyle(
                      color: isDone || isCancelled
                          ? Colors.grey[500]
                          : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      decoration: isCancelled
                          ? TextDecoration.lineThrough
                          : TextDecoration.none),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(
                  isSending
                      ? '${(item.progress * 100).toStringAsFixed(0)}%  •  ${_sizeStr(item.file.size)}'
                      : _sizeStr(item.file.size),
                  style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            ]),
          ),
          // Cancel / remove button
          if (isSending || item.status == QueueStatus.pending)
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: Colors.grey),
              onPressed: () => _cancelItem(item),
              tooltip: 'Cancel',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            )
          else
            IconButton(
              icon: Icon(Icons.delete_outline, size: 18, color: Colors.grey[700]),
              onPressed: () => setState(() => _queue.remove(item)),
              tooltip: 'Remove',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ]),

        // Progress bar while sending
        if (isSending) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: item.progress > 0 ? item.progress : null,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.indigoAccent),
              minHeight: 3,
            ),
          ),
        ],
      ]),
    );
  }

  // ── History list ──────────────────────────────────────────────────────────

  Widget _buildHistoryList(HistoryType type) {
    final entries = _history.where((h) => h.type == type).toList();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: entries.length,
        separatorBuilder: (context, index) =>
            Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
        itemBuilder: (context, i) {
          final e = entries[i];
          return ListTile(
            dense: true,
            leading: Icon(
              type == HistoryType.fileSent
                  ? Icons.insert_drive_file
                  : Icons.text_fields,
              color: Colors.greenAccent.withValues(alpha: 0.8),
              size: 18,
            ),
            title: Text(e.label,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            trailing: Text(_timeStr(e.time),
                style: TextStyle(color: Colors.grey[600], fontSize: 10)),
          );
        },
      ),
    );
  }

  // ── Action button ─────────────────────────────────────────────────────────

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    required bool active,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF4F46E5)])
                : null,
            color: active ? null : Colors.grey[800],
            borderRadius: BorderRadius.circular(14),
          ),
          child: Container(
            alignment: Alignment.center,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
      ),
    );
  }
}
