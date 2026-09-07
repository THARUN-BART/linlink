import 'dart:convert';
import 'dart:io';
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

  Future<void> _showUploadDialog() async {
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
        title: const Text('Upload File to Linux ⬆️'),
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
            label: const Text('Upload over TCP'),
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
            content: Text('✅ Uploaded "$filename" to Linux!'),
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
        onPressed: _showUploadDialog,
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
