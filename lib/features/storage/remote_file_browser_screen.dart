import 'dart:convert';
import 'dart:io';
import 'package:android_file_picker/android_file_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_picker_linux/file_picker_linux.dart';
import 'package:flutter/material.dart';
import '../pairing/pairing_service.dart';

class RemoteFileBrowserScreen extends StatefulWidget {
  final PairedCompanion companion;

  const RemoteFileBrowserScreen({
    super.key,
    required this.companion,
  });

  @override
  State<RemoteFileBrowserScreen> createState() => _RemoteFileBrowserScreenState();
}

class _RemoteFileBrowserScreenState extends State<RemoteFileBrowserScreen> {
  String _currentPath = '';
  String? _parentPath;
  String? _homePath;
  String? _transfersPath;
  List<Map<String, dynamic>> _entries = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDirectory(null);
  }

  Future<void> _loadDirectory(String? path) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final uri = Uri.parse('${widget.companion.baseUrl}/api/fs/list');
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      final payload = <String, dynamic>{
        'token': widget.companion.token,
      };
      if (path != null) {
        payload['path'] = path;
      }
      req.write(jsonEncode(payload));

      final res = await req.close();
      final body = await utf8.decoder.bind(res).join();

      if (res.statusCode == 200) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        setState(() {
          _currentPath = json['current_path'] as String;
          _parentPath = json['parent_path'] as String?;
          _homePath = json['home_path'] as String?;
          _transfersPath = json['transfers_path'] as String?;
          _entries = (json['entries'] as List)
              .map((e) => e as Map<String, dynamic>)
              .toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to load directory (HTTP ${res.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not reach Linux companion over TCP: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadFile(String remotePath, String filename) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('Downloading "$filename" from Linux over TCP...')),
          ],
        ),
      ),
    );

    try {
      final downloadUri = Uri.parse(
        '${widget.companion.baseUrl}/api/fs/download?token=${widget.companion.token}&path=${Uri.encodeComponent(remotePath)}',
      );
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
      final req = await client.getUrl(downloadUri);
      final res = await req.close();

      if (res.statusCode == 200) {
        Directory targetDir = Directory('/storage/emulated/0/Download/LinLink');
        try {
          if (!await targetDir.exists()) {
            await targetDir.create(recursive: true);
          }
        } catch (_) {
          targetDir = Directory('/storage/emulated/0/Download');
        }

        final localFile = File('${targetDir.path}/$filename');
        final sink = localFile.openWrite();
        await res.cast<List<int>>().pipe(sink);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.teal.shade800,
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.greenAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Saved to Download/LinLink/$filename'),
                ),
              ],
            ),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Text('Download failed (HTTP ${res.statusCode})'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade800,
          content: Text('Error downloading file: $e'),
        ),
      );
    }
  }

  Future<void> _pickAndUploadFiles() async {
    // Explicitly ensure the platform picker implementation is registered
    if (Platform.isAndroid) {
      try {
        FilePickerAndroid.registerWith();
      } catch (_) {}
    } else if (Platform.isLinux) {
      try {
        FilePickerLinux.registerWith();
      } catch (_) {}
    }

    List<PlatformFile> files = [];
    try {
      files = await FilePicker.pickFiles(
        type: FileType.any,
      );
    } catch (e) {
      debugPrint('FilePicker error: $e. Falling back to local storage file picker...');
      await _showLocalDeviceFilePicker();
      return;
    }

    if (files.isEmpty) {
      return; // User cancelled file manager selection
    }

    int successCount = 0;
    final total = files.length;

    for (int i = 0; i < total; i++) {
      final platformFile = files[i];
      final filename = platformFile.name;
      final fileSize = await platformFile.length();
      final sizeStr = _formatBytes(fileSize);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.cyanAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  total > 1
                      ? 'Uploading (${i + 1}/$total) "$filename" ($sizeStr)...'
                      : 'Uploading "$filename" ($sizeStr) to Linux...',
                ),
              ),
            ],
          ),
        ),
      );

      final success = await _uploadSingleFile(platformFile, fileSize);
      if (success) {
        successCount++;
      }
    }

    if (!mounted) return;

    if (successCount == total) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.teal.shade800,
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.greenAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  total == 1
                      ? '✅ "${files.first.name}" uploaded to Linux!'
                      : '✅ Successfully uploaded $total files to Linux!',
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange.shade900,
          content: Text(
            '⚠️ Uploaded $successCount of $total files. Some files failed to upload.',
          ),
        ),
      );
    }

    _loadDirectory(_currentPath.isEmpty ? null : _currentPath);
  }

  Future<void> _showLocalDeviceFilePicker() async {
    String currentLocalPath = '/storage/emulated/0';
    if (!Directory(currentLocalPath).existsSync()) {
      currentLocalPath = Directory.current.path;
    }

    final selectedFile = await showModalBottomSheet<File>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final dir = Directory(currentLocalPath);
            List<FileSystemEntity> entities = [];
            try {
              if (dir.existsSync()) {
                entities = dir.listSync()
                  ..sort((a, b) {
                    final aIsDir = a is Directory;
                    final bIsDir = b is Directory;
                    if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
                    return a.path.toLowerCase().compareTo(b.path.toLowerCase());
                  });
              }
            } catch (_) {}

            return FractionallySizedBox(
              heightFactor: 0.85,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.white12)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.folder, color: Colors.cyanAccent),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Select File from Device',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (dir.parent.path != dir.path)
                              IconButton(
                                icon: const Icon(Icons.arrow_upward, size: 20),
                                tooltip: 'Up one folder',
                                onPressed: () {
                                  setModalState(() {
                                    currentLocalPath = dir.parent.path;
                                  });
                                },
                              ),
                            Expanded(
                              child: Text(
                                currentLocalPath,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                  fontFamily: 'monospace',
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: entities.isEmpty
                        ? const Center(child: Text('No files found in directory'))
                        : ListView.builder(
                            itemCount: entities.length,
                            itemBuilder: (context, index) {
                              final item = entities[index];
                              final isDirectory = item is Directory;
                              final name = item.uri.pathSegments.where((s) => s.isNotEmpty).last;

                              if (name.startsWith('.')) return const SizedBox.shrink();

                              return ListTile(
                                leading: Icon(
                                  isDirectory ? Icons.folder : Icons.insert_drive_file,
                                  color: isDirectory ? Colors.amber : Colors.cyanAccent,
                                ),
                                title: Text(name, style: const TextStyle(fontSize: 14)),
                                onTap: () {
                                  if (isDirectory) {
                                    setModalState(() {
                                      currentLocalPath = item.path;
                                    });
                                  } else if (item is File) {
                                    Navigator.pop(context, item);
                                  }
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (selectedFile != null) {
      final filename = selectedFile.uri.pathSegments.last;
      final fileSize = await selectedFile.length();
      final sizeStr = _formatBytes(fileSize);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Uploading "$filename" ($sizeStr) to Linux...'),
        ),
      );

      final success = await _uploadRawFile(selectedFile);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.teal.shade800,
            content: Text('✅ "$filename" uploaded to Linux!'),
          ),
        );
        _loadDirectory(_currentPath.isEmpty ? null : _currentPath);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Text('❌ Upload failed for "$filename"'),
          ),
        );
      }
    }
  }

  Future<bool> _uploadRawFile(File file) async {
    final filename = file.uri.pathSegments.last;
    final uploadUri = Uri.parse(
      '${widget.companion.baseUrl}/api/fs/upload?token=${widget.companion.token}&dest_dir=${Uri.encodeComponent(_currentPath)}&filename=${Uri.encodeComponent(filename)}',
    );

    final client = HttpClient()..connectionTimeout = const Duration(minutes: 5);

    try {
      final req = await client.postUrl(uploadUri);
      req.headers.contentType = ContentType.binary;
      req.contentLength = await file.length();
      await file.openRead().cast<List<int>>().pipe(req);
      final res = await req.close();
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Error uploading raw file $filename: $e');
      return false;
    }
  }

  Future<bool> _uploadSingleFile(PlatformFile platformFile, int fileSize) async {
    final filename = platformFile.name;
    final uploadUri = Uri.parse(
      '${widget.companion.baseUrl}/api/fs/upload?token=${widget.companion.token}&dest_dir=${Uri.encodeComponent(_currentPath)}&filename=${Uri.encodeComponent(filename)}',
    );

    final client = HttpClient()..connectionTimeout = const Duration(minutes: 5);

    try {
      final req = await client.postUrl(uploadUri);
      req.headers.contentType = ContentType.binary;
      req.contentLength = fileSize;

      if (platformFile.path != null && File(platformFile.path!).existsSync()) {
        final localFile = File(platformFile.path!);
        await localFile.openRead().cast<List<int>>().pipe(req);
      } else {
        await platformFile.readAsByteStream().cast<List<int>>().pipe(req);
      }

      final res = await req.close();
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Error uploading $filename: $e');
      return false;
    }
  }

  Future<void> _showCreateNoteDialog() async {
    final nameController = TextEditingController(
      text: 'note_${DateTime.now().millisecondsSinceEpoch}.txt',
    );
    final contentController = TextEditingController(
      text: 'Sent from Android (${widget.companion.deviceName}) over TCP\n'
          'Date: ${DateTime.now().toLocal()}\n',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Text Note on Linux 📝'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Destination directory on Linux:\n$_currentPath',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'File Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'File Content',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.upload),
            label: const Text('Create File'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final filename = nameController.text.trim();
    final content = contentController.text;

    try {
      final uploadUri = Uri.parse(
        '${widget.companion.baseUrl}/api/fs/upload?token=${widget.companion.token}&dest_dir=${Uri.encodeComponent(_currentPath)}&filename=${Uri.encodeComponent(filename)}',
      );
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final req = await client.postUrl(uploadUri);
      req.headers.contentType = ContentType.binary;
      final bytes = utf8.encode(content);
      req.contentLength = bytes.length;
      req.add(bytes);
      final res = await req.close();

      if (res.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.teal.shade800,
            content: Text('✅ Created "$filename" on Linux!'),
          ),
        );
        _loadDirectory(_currentPath);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Text('Upload failed (HTTP ${res.statusCode})'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade800,
          content: Text('Upload error: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Linux Files 💻'),
        actions: [
          IconButton(
            icon: const Icon(Icons.note_add_outlined),
            tooltip: 'Create Text Note',
            onPressed: _showCreateNoteDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _loadDirectory(_currentPath.isEmpty ? null : _currentPath),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.cyan.shade700,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.upload_file),
        label: const Text('Upload to Linux'),
        onPressed: _pickAndUploadFiles,
      ),
      body: Column(
        children: [
          // Path navigation bar & shortcut buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.black26,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.folder_open, size: 18, color: Colors.cyanAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentPath.isEmpty ? 'Loading…' : _currentPath,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (_parentPath != null)
                      ActionChip(
                        avatar: const Icon(Icons.arrow_upward, size: 14),
                        label: const Text('Up (..)'),
                        onPressed: () => _loadDirectory(_parentPath),
                      ),
                    const SizedBox(width: 8),
                    if (_homePath != null)
                      ActionChip(
                        avatar: const Icon(Icons.home, size: 14),
                        label: const Text('Home (~)'),
                        onPressed: () => _loadDirectory(_homePath),
                      ),
                    const SizedBox(width: 8),
                    if (_transfersPath != null)
                      ActionChip(
                        avatar: const Icon(Icons.download, size: 14),
                        label: const Text('Transfers'),
                        onPressed: () => _loadDirectory(_transfersPath),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // File / folder listing
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                              const SizedBox(height: 12),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () => _loadDirectory(null),
                                child: const Text('Retry Home'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _entries.isEmpty
                        ? const Center(
                            child: Text(
                              'Directory is empty.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _entries.length,
                            separatorBuilder: (context, index) => const Divider(height: 1, indent: 56),
                            itemBuilder: (context, index) {
                              final item = _entries[index];
                              final isDir = item['is_dir'] as bool? ?? false;
                              final name = item['name'] as String? ?? '';
                              final size = item['size'] as int? ?? 0;
                              final fullPath = '$_currentPath/$name';

                              return ListTile(
                                leading: Icon(
                                  isDir ? Icons.folder : Icons.insert_drive_file,
                                  color: isDir ? Colors.cyanAccent : Colors.white70,
                                ),
                                title: Text(
                                  name,
                                  style: TextStyle(
                                    fontWeight: isDir ? FontWeight.bold : FontWeight.normal,
                                    color: isDir ? Colors.cyanAccent : Colors.white,
                                  ),
                                ),
                                subtitle: Text(
                                  isDir ? 'Folder' : _formatBytes(size),
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                trailing: isDir
                                    ? const Icon(Icons.chevron_right, color: Colors.grey)
                                    : IconButton(
                                        icon: const Icon(Icons.download, color: Colors.greenAccent),
                                        tooltip: 'Download over TCP',
                                        onPressed: () => _downloadFile(fullPath, name),
                                      ),
                                onTap: () {
                                  if (isDir) {
                                    _loadDirectory(fullPath);
                                  } else {
                                    _downloadFile(fullPath, name);
                                  }
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1000000000) {
      return '${(bytes / 1000000000).toStringAsFixed(1)} GB';
    } else if (bytes >= 1000000) {
      return '${(bytes / 1000000).toStringAsFixed(1)} MB';
    } else if (bytes >= 1000) {
      return '${(bytes / 1000).toStringAsFixed(1)} KB';
    } else {
      return '$bytes B';
    }
  }
}
