import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:recpy/services/storage_service.dart';

class NetworkService {
  ServerSocket? _serverSocket;
  bool _isListening = false;

  bool get isListening => _isListening;

  // Get local IP addresses
  static Future<List<String>> getLocalIps() async {
    List<String> ips = [];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          ips.add(addr.address);
        }
      }
    } catch (e) {
      // ignore
    }
    return ips.isEmpty ? ['127.0.0.1'] : ips;
  }

  // Send Text
  static Future<void> sendText({
    required String ip,
    required int port,
    required String text,
    required Function(double progress) onProgress,
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
      
      final magic = utf8.encode('RECPY');
      final type = [1];
      final textBytes = utf8.encode(text);
      final lenBytes = Uint8List(4);
      ByteData.view(lenBytes.buffer).setUint32(0, textBytes.length, Endian.big);

      socket.add(magic);
      socket.add(type);
      socket.add(lenBytes);
      socket.add(textBytes);
      await socket.flush();
      onProgress(1.0);
    } finally {
      await socket?.close();
    }
  }

  // Send Files
  static Future<void> sendFiles({
    required String ip,
    required int port,
    required List<File> files,
    required Function(String filename, double progress) onProgress,
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 15));
      
      final magic = utf8.encode('RECPY');
      final type = [2];
      
      final countBytes = Uint8List(4);
      ByteData.view(countBytes.buffer).setUint32(0, files.length, Endian.big);

      socket.add(magic);
      socket.add(type);
      socket.add(countBytes);
      await socket.flush();

      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final filename = p.basename(file.path);
        final filenameBytes = utf8.encode(filename);
        final nameLenBytes = Uint8List(4);
        ByteData.view(nameLenBytes.buffer).setUint32(0, filenameBytes.length, Endian.big);

        final fileBytes = await file.readAsBytes();
        final fileLenBytes = Uint8List(8);
        ByteData.view(fileLenBytes.buffer).setUint64(0, fileBytes.length, Endian.big);

        socket.add(nameLenBytes);
        socket.add(filenameBytes);
        socket.add(fileLenBytes);

        // Send file content in chunks to show progress
        const int chunkSize = 65536; // 64KB
        int sentBytes = 0;
        while (sentBytes < fileBytes.length) {
          int end = sentBytes + chunkSize;
          if (end > fileBytes.length) {
            end = fileBytes.length;
          }
          socket.add(fileBytes.sublist(sentBytes, end));
          await socket.flush();
          sentBytes = end;
          onProgress(filename, sentBytes / fileBytes.length);
        }
      }
    } finally {
      await socket?.close();
    }
  }

  // Start Server
  Future<void> startServer({
    required int port,
    required Function(String clientIp, String text) onTextReceived,
    required Function(String clientIp, String filename, String savedPath) onFileReceived,
    required Function(String clientIp, String info, double progress) onTransferProgress,
    required Function(String status) onStatusChanged,
    required Function(String error) onError,
  }) async {
    if (_isListening) return;

    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _isListening = true;
      onStatusChanged("Listening on port $port...");

      _serverSocket!.listen(
        (Socket socket) {
          _handleClient(
            socket,
            onTextReceived,
            onFileReceived,
            onTransferProgress,
            onError,
          );
        },
        onError: (e) {
          onError("Server error: $e");
          stopServer(onStatusChanged);
        },
      );
    } catch (e) {
      onError("Failed to bind server to port $port: $e");
      _isListening = false;
      onStatusChanged("Stopped");
    }
  }

  // Stop Server
  void stopServer(Function(String status) onStatusChanged) {
    if (!_isListening) return;
    _serverSocket?.close();
    _serverSocket = null;
    _isListening = false;
    onStatusChanged("Stopped");
  }

  // Handle client socket connection
  void _handleClient(
    Socket socket,
    Function(String clientIp, String text) onTextReceived,
    Function(String clientIp, String filename, String savedPath) onFileReceived,
    Function(String clientIp, String info, double progress) onTransferProgress,
    Function(String error) onError,
  ) {
    final String clientIp = socket.remoteAddress.address;
    final BytesBuilder builder = BytesBuilder();
    
    // Parse State
    // 0: Reading Magic (5 bytes) + Type (1 byte)
    // 1: Reading Text - Length (4 bytes)
    // 2: Reading Text - Content (length bytes)
    // 3: Reading Files - Count (4 bytes)
    // 4: Reading Files - File Header (NameLen 4 bytes)
    // 5: Reading Files - File Name (NameLen bytes)
    // 6: Reading Files - File Content Length (8 bytes)
    // 7: Reading Files - File Content (ContentLen bytes)
    int state = 0;
    
    int expectedLength = 6; // Initially looking for 5 bytes magic + 1 byte type
    int commandType = 0;
    
    int textLength = 0;
    
    int fileCount = 0;
    int currentFileIndex = 0;
    int filenameLength = 0;
    String currentFilename = "";
    int currentFileContentLength = 0;
    
    // For streaming file content to disk
    File? tempFile;
    IOSink? fileSink;
    int fileBytesWritten = 0;

    cleanup() async {
      try {
        if (fileSink != null) {
          await fileSink!.flush();
          await fileSink!.close();
          fileSink = null;
        }
      } catch (_) {}
      try {
        socket.close();
      } catch (_) {}
    }

    void processBuffer() async {
      try {
        bool progress = true;
        while (progress) {
          if (state == 7) {
            // We are streaming file data directly to disk
            if (builder.length == 0) {
              progress = false;
              break;
            }
            
            final remainingData = builder.takeBytes();
            int bytesToUse = remainingData.length;
            int remainingForThisFile = currentFileContentLength - fileBytesWritten;
            if (bytesToUse > remainingForThisFile) {
              bytesToUse = remainingForThisFile;
            }
            
            if (fileSink != null) {
              fileSink!.add(remainingData.sublist(0, bytesToUse));
              fileBytesWritten += bytesToUse;
              
              double progressVal = currentFileContentLength > 0 ? (fileBytesWritten / currentFileContentLength) : 1.0;
              onTransferProgress(clientIp, "Receiving $currentFilename (${currentFileIndex + 1}/$fileCount)", progressVal);
            }
            
            if (bytesToUse < remainingData.length) {
              builder.add(remainingData.sublist(bytesToUse));
            }
            
            if (fileBytesWritten >= currentFileContentLength) {
              // File is complete!
              await fileSink!.flush();
              await fileSink!.close();
              fileSink = null;
              
              final downloadDir = await _getDownloadDirectory();
              final finalPath = p.join(downloadDir.path, currentFilename);
              
              String safePath = finalPath;
              int counter = 1;
              while (await File(safePath).exists()) {
                final extension = p.extension(currentFilename);
                final base = p.basenameWithoutExtension(currentFilename);
                safePath = p.join(downloadDir.path, "${base}_$counter$extension");
                counter++;
              }
              
              if (tempFile != null) {
                // Use copy+delete instead of rename to avoid cross-device
                // link errors (errno 18) when temp dir and Downloads are
                // on different Android filesystem partitions.
                await tempFile!.copy(safePath);
                await tempFile!.delete();
                tempFile = null;
              }
              
              onFileReceived(clientIp, currentFilename, safePath);
              
              currentFileIndex++;
              if (currentFileIndex >= fileCount) {
                cleanup();
                progress = false;
                break;
              } else {
                state = 4;
                expectedLength = 4;
              }
            }
          } else {
            // Buffer-based state machine
            final currentBuffer = builder.takeBytes();
            if (currentBuffer.length < expectedLength) {
              builder.add(currentBuffer);
              progress = false;
              break;
            }
            
            final targetBytes = currentBuffer.sublist(0, expectedLength);
            final remainder = currentBuffer.sublist(expectedLength);
            builder.add(remainder);
            
            if (state == 0) {
              final magicStr = utf8.decode(targetBytes.sublist(0, 5), allowMalformed: true);
              if (magicStr != 'RECPY') {
                onError("Invalid protocol: magic header mismatch");
                cleanup();
                progress = false;
                break;
              }
              commandType = targetBytes[5];
              if (commandType == 1) {
                state = 1;
                expectedLength = 4;
              } else if (commandType == 2) {
                state = 3;
                expectedLength = 4;
              } else {
                onError("Unknown command type: $commandType");
                cleanup();
                progress = false;
                break;
              }
            } else if (state == 1) {
              textLength = ByteData.sublistView(targetBytes).getUint32(0, Endian.big);
              state = 2;
              expectedLength = textLength;
            } else if (state == 2) {
              final text = utf8.decode(targetBytes);
              onTextReceived(clientIp, text);
              cleanup();
              progress = false;
              break;
            } else if (state == 3) {
              fileCount = ByteData.sublistView(targetBytes).getUint32(0, Endian.big);
              currentFileIndex = 0;
              state = 4;
              expectedLength = 4;
            } else if (state == 4) {
              filenameLength = ByteData.sublistView(targetBytes).getUint32(0, Endian.big);
              state = 5;
              expectedLength = filenameLength;
            } else if (state == 5) {
              currentFilename = utf8.decode(targetBytes);
              state = 6;
              expectedLength = 8;
            } else if (state == 6) {
              currentFileContentLength = ByteData.sublistView(targetBytes).getUint64(0, Endian.big);
              state = 7;
              fileBytesWritten = 0;
              expectedLength = 0;
              
              final tempDir = await getTemporaryDirectory();
              tempFile = File(p.join(tempDir.path, 'recpy_temp_${DateTime.now().millisecondsSinceEpoch}'));
              fileSink = tempFile!.openWrite();
              
              onTransferProgress(clientIp, "Receiving $currentFilename (${currentFileIndex + 1}/$fileCount)", 0.0);
            }
          }
        }
      } catch (e) {
        onError("Parser loop error: $e");
        cleanup();
      }
    }

    socket.listen(
      (Uint8List data) {
        builder.add(data);
        processBuffer();
      },
      onError: (e) {
        onError("Socket communication error: $e");
        cleanup();
      },
      onDone: () {
        cleanup();
      },
    );
  }

  // Get download directory helper
  static Future<Directory> _getDownloadDirectory() async {
    final savedPath = await StorageService.getDownloadPath();
    final savedDir = Directory(savedPath);
    if (await savedDir.exists()) {
      return savedDir;
    }
    // Fallback: try to create it; if not possible, use app documents dir
    try {
      await savedDir.create(recursive: true);
      return savedDir;
    } catch (_) {
      return await getApplicationDocumentsDirectory();
    }
  }
}
