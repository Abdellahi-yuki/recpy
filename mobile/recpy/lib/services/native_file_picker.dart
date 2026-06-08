import 'package:flutter/services.dart';

/// A file entry returned by the native picker.
/// Contains the Android content URI and metadata — no filesystem path needed.
class NativeFile {
  final String uri;
  final String name;
  final int size;

  const NativeFile({required this.uri, required this.name, required this.size});

  @override
  String toString() => 'NativeFile($name, ${size}B)';
}

class NativeFilePicker {
  static const _methodChannel = MethodChannel('io.recpy.app/file_picker');

  /// Opens the system file picker and returns instantly with uri+name+size.
  /// No file copying — just ContentResolver metadata queries.
  static Future<List<NativeFile>?> pickFiles() async {
    final result = await _methodChannel.invokeMethod<List<dynamic>>('pickFiles');
    if (result == null) return null;
    return result.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return NativeFile(
        uri: m['uri'] as String,
        name: m['name'] as String,
        size: (m['size'] as num).toInt(),
      );
    }).toList();
  }

  /// Returns a Stream of [Uint8List] chunks read directly from the content URI
  /// via Android ContentResolver — zero temp-file copy.
  ///
  /// Each file gets its own uniquely-named EventChannel to avoid broadcast
  /// stream conflicts when sending multiple files sequentially.
  static Stream<Uint8List> openReadStream(NativeFile file, {int chunkSize = 262144}) {
    // Unique channel per stream so multiple files don't collide
    final channelName = 'io.recpy.app/file_stream/${Uri.encodeComponent(file.uri)}';
    final channel = EventChannel(channelName);
    return channel
        .receiveBroadcastStream({'uri': file.uri, 'chunkSize': chunkSize})
        .map((chunk) {
          // StandardMessageCodec delivers ByteArray as Uint8List
          if (chunk is Uint8List) return chunk;
          // Fallback: handle List<dynamic> just in case
          if (chunk is List) return Uint8List.fromList(chunk.cast<int>());
          throw StateError('Unexpected chunk type: ${chunk.runtimeType}');
        });
  }
}
