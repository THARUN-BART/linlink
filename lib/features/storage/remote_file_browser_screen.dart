import 'dart:convert';
import 'dart:io';
import 'package:android_file_picker/android_file_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_picker_linux/file_picker_linux.dart';
import 'package:flutter/material.dart';
import '../../theme/linlink_theme.dart';
import '../pairing/pairing_service.dart';

class RemoteFileBrowserScreen extends StatefulWidget {
  final PairedCompanion? companion;
  final VoidCallback? onRequestPair;

  const RemoteFileBrowserScreen({
    super.key,
    required this.companion,
    this.onRequestPair,
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
  bool _isLoading = false;
  String? _errorMessage;

  bool _isSearchOpen = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Transfer tracking
  bool _isTransferring = false;
  String _transferFilename = '';
  String _transferBytesText = '';

  @override
  void initState() {
    super.initState();
    if (widget.companion != null) {
      _loadDirectory(null);
    }
  }

  @override
  void didUpdateWidget(covariant RemoteFileBrowserScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.companion != null && widget.companion != oldWidget.companion) {
      _loadDirectory(null);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDirectory(String? path) async {
    if (widget.companion == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final uri = Uri.parse('${widget.companion!.baseUrl}/api/fs/list');
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      final payload = <String, dynamic>{
        'token': widget.companion!.token,
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
    if (widget.companion == null) return;

    _showTransferDialog(
      filename: filename,
      isUpload: false,
    );

    try {
      final downloadUri = Uri.parse(
        '${widget.companion!.baseUrl}/api/fs/download?token=${widget.companion!.token}&path=${Uri.encodeComponent(remotePath)}',
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

        if (mounted) {
          setState(() {
            _isTransferring = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: LinLinkColors.secondaryContainer,
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Downloaded to Download/LinLink/$filename'),
                  ),
                ],
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          setState(() => _isTransferring = false);
          _showError('Download failed (HTTP ${res.statusCode})');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isTransferring = false);
        _showError('Error downloading: $e');
      }
    }
  }

  Future<void> _pickAndUploadFiles() async {
    if (widget.companion == null) {
      widget.onRequestPair?.call();
      return;
    }

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
      files = await FilePicker.pickFiles(type: FileType.any);
    } catch (e) {
      _showLocalDeviceFilePicker();
      return;
    }

    if (files.isEmpty) return;

    for (final file in files) {
      final fileSize = await file.length();
      _showTransferDialog(filename: file.name, isUpload: true);
      final success = await _uploadSingleFile(file, fileSize);
      if (mounted) setState(() => _isTransferring = false);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: LinLinkColors.secondaryContainer,
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Uploaded "${file.name}" to Linux!')),
              ],
            ),
          ),
        );
      }
    }

    _loadDirectory(_currentPath.isEmpty ? null : _currentPath);
  }

  Future<bool> _uploadSingleFile(PlatformFile platformFile, int fileSize) async {
    final filename = platformFile.name;
    final uploadUri = Uri.parse(
      '${widget.companion!.baseUrl}/api/fs/upload?token=${widget.companion!.token}&dest_dir=${Uri.encodeComponent(_currentPath)}&filename=${Uri.encodeComponent(filename)}',
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
      return false;
    }
  }

  Future<void> _showLocalDeviceFilePicker() async {
    String currentLocalPath = '/storage/emulated/0';
    if (!Directory(currentLocalPath).existsSync()) {
      currentLocalPath = Directory.current.path;
    }

    final selectedFile = await showModalBottomSheet<File>(
      context: context,
      isScrollControlled: true,
      backgroundColor: LinLinkColors.surfaceContainer,
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
                    child: Row(
                      children: [
                        const Icon(Icons.folder, color: LinLinkColors.primaryContainer),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Select File to Upload',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: entities.length,
                      itemBuilder: (context, index) {
                        final item = entities[index];
                        final isDirectory = item is Directory;
                        final name = item.uri.pathSegments.where((s) => s.isNotEmpty).last;

                        if (name.startsWith('.')) return const SizedBox.shrink();

                        return ListTile(
                          leading: Icon(
                            isDirectory ? Icons.folder : Icons.insert_drive_file,
                            color: isDirectory ? Colors.amber : LinLinkColors.primaryContainer,
                          ),
                          title: Text(name, style: const TextStyle(fontSize: 14)),
                          onTap: () {
                            if (isDirectory) {
                              setModalState(() => currentLocalPath = item.path);
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
      _showTransferDialog(filename: filename, isUpload: true);
      final success = await _uploadRawFile(selectedFile);
      if (mounted) setState(() => _isTransferring = false);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: LinLinkColors.secondaryContainer,
            content: Text('✅ "$filename" uploaded to Linux!'),
          ),
        );
        _loadDirectory(_currentPath.isEmpty ? null : _currentPath);
      }
    }
  }

  Future<bool> _uploadRawFile(File file) async {
    final filename = file.uri.pathSegments.last;
    final uploadUri = Uri.parse(
      '${widget.companion!.baseUrl}/api/fs/upload?token=${widget.companion!.token}&dest_dir=${Uri.encodeComponent(_currentPath)}&filename=${Uri.encodeComponent(filename)}',
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
      return false;
    }
  }

  void _showTransferDialog({required String filename, required bool isUpload}) {
    setState(() {
      _isTransferring = true;
      _transferFilename = filename;
      _transferBytesText = isUpload ? 'Uploading to Linux...' : 'Downloading from Linux...';
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: LinLinkColors.errorContainer, content: Text(message)),
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

  @override
  Widget build(BuildContext context) {
    final isLinked = widget.companion != null;

    if (!isLinked) {
      return _buildUnlinkedView();
    }

    final filteredEntries = _searchQuery.isEmpty
        ? _entries
        : _entries.where((e) {
            final name = (e['name'] as String? ?? '').toLowerCase();
            return name.contains(_searchQuery.toLowerCase());
          }).toList();

    final dirs = filteredEntries.where((e) => e['is_dir'] == true).toList();
    final files = filteredEntries.where((e) => e['is_dir'] != true).toList();

    final int totalBytes = files.fold(0, (acc, item) => acc + (item['size'] as int? ?? 0));

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: LinLinkColors.primary,
        foregroundColor: LinLinkColors.onPrimary,
        icon: const Icon(Icons.upload_file, size: 20),
        label: const Text('Upload to Linux', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        onPressed: _pickAndUploadFiles,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Directory Navigation & Toolbar Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: LinLinkColors.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: LinLinkColors.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top path row with Up and Refresh
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: LinLinkColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_upward, size: 16),
                          tooltip: 'Go to parent directory',
                          color: _parentPath != null ? LinLinkColors.onSurface : LinLinkColors.outline,
                          onPressed: _parentPath != null ? () => _loadDirectory(_parentPath) : null,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: LinLinkColors.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: LinLinkColors.outlineVariant),
                          ),
                          child: Text(
                            _currentPath.isEmpty ? '~' : _currentPath,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: LinLinkColors.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(_isSearchOpen ? Icons.close : Icons.search, size: 20),
                        color: LinLinkColors.onSurfaceVariant,
                        tooltip: 'Search folder',
                        onPressed: () {
                          setState(() {
                            _isSearchOpen = !_isSearchOpen;
                            if (!_isSearchOpen) {
                              _searchController.clear();
                              _searchQuery = '';
                            }
                          });
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        color: LinLinkColors.onSurfaceVariant,
                        tooltip: 'Refresh folder',
                        onPressed: () => _loadDirectory(_currentPath.isEmpty ? null : _currentPath),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ),

                  // Search Field (when opened)
                  if (_isSearchOpen) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _searchController,
                      autofocus: true,
                      style: const TextStyle(color: LinLinkColors.onSurface, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Filter files & folders...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        prefixIcon: const Icon(Icons.search, size: 18, color: LinLinkColors.outline),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Location Shortcut Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildChip(
                          icon: Icons.home_outlined,
                          label: 'Home (~)',
                          isActive: _currentPath == _homePath,
                          onTap: () => _loadDirectory(_homePath),
                        ),
                        const SizedBox(width: 8),
                        _buildChip(
                          icon: Icons.download_outlined,
                          label: 'Transfers',
                          isActive: _currentPath == _transfersPath,
                          onTap: () => _loadDirectory(_transfersPath),
                        ),
                        const SizedBox(width: 8),
                        _buildChip(
                          icon: Icons.computer_outlined,
                          label: 'Root (/)',
                          isActive: _currentPath == '/',
                          onTap: () => _loadDirectory('/'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (_isTransferring) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: LinLinkColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: LinLinkColors.primary.withAlpha(100)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: LinLinkColors.primary),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _transferBytesText,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: LinLinkColors.primary),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          color: LinLinkColors.onSurfaceVariant,
                          onPressed: () => setState(() => _isTransferring = false),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _transferFilename,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, fontFamily: 'monospace'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Content or Loading or Error
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(48.0),
                  child: CircularProgressIndicator(color: LinLinkColors.primary),
                ),
              )
            else if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: LinLinkColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: LinLinkColors.outlineVariant),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline, size: 32, color: LinLinkColors.error),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: LinLinkColors.onSurfaceVariant, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton(
                      onPressed: () => _loadDirectory(null),
                      child: const Text('Return to Home folder'),
                    ),
                  ],
                ),
              )
            else ...[
              // Directories Section
              if (dirs.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Folders (${dirs.length})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: LinLinkColors.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: LinLinkColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: LinLinkColors.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: dirs.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = dirs[index];
                      final name = item['name'] as String? ?? '';
                      final fullPath = '$_currentPath/$name';

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                        leading: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: LinLinkColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.folder, color: LinLinkColors.primary, size: 18),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: LinLinkColors.onSurface,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 18, color: LinLinkColors.outline),
                        onTap: () => _loadDirectory(fullPath),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
              ],

              // Files Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Files (${files.length})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: LinLinkColors.onSurface,
                    ),
                  ),
                  Text(
                    _formatBytes(totalBytes),
                    style: const TextStyle(fontSize: 11, color: LinLinkColors.onSurfaceVariant, fontFamily: 'monospace'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (files.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: LinLinkColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: LinLinkColors.outlineVariant),
                  ),
                  child: const Center(
                    child: Text('No files in this folder', style: TextStyle(color: LinLinkColors.outline, fontSize: 13)),
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: LinLinkColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: LinLinkColors.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: files.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = files[index];
                      final name = item['name'] as String? ?? '';
                      final size = item['size'] as int? ?? 0;
                      final fullPath = '$_currentPath/$name';

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                        leading: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: LinLinkColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(_getFileIcon(name), color: LinLinkColors.onSurfaceVariant, size: 18),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: LinLinkColors.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          _formatBytes(size),
                          style: const TextStyle(fontSize: 11, color: LinLinkColors.onSurfaceVariant, fontFamily: 'monospace'),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.download, color: LinLinkColors.primary, size: 20),
                          tooltip: 'Download to device',
                          onPressed: () => _downloadFile(fullPath, name),
                        ),
                        onTap: () => _downloadFile(fullPath, name),
                      );
                    },
                  ),
                ),
            ],

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildChip({
    required IconData icon,
    required String label,
    required bool isActive,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? LinLinkColors.primaryContainer : LinLinkColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? LinLinkColors.primary : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isActive ? LinLinkColors.onPrimaryContainer : LinLinkColors.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isActive ? LinLinkColors.onPrimaryContainer : LinLinkColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.zip') || lower.endsWith('.tar') || lower.endsWith('.gz') || lower.endsWith('.xz')) {
      return Icons.folder_zip_outlined;
    }
    if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.svg') || lower.endsWith('.gif')) {
      return Icons.image_outlined;
    }
    if (lower.endsWith('.pdf') || lower.endsWith('.doc') || lower.endsWith('.txt') || lower.endsWith('.md') || lower.endsWith('.json')) {
      return Icons.description_outlined;
    }
    if (lower.endsWith('.mp3') || lower.endsWith('.wav') || lower.endsWith('.flac')) {
      return Icons.music_note_outlined;
    }
    if (lower.endsWith('.mp4') || lower.endsWith('.mkv') || lower.endsWith('.mov')) {
      return Icons.video_file_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Widget _buildUnlinkedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: LinLinkColors.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: LinLinkColors.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: LinLinkColors.surfaceContainerHigh,
                ),
                child: const Icon(Icons.folder_shared_outlined, size: 24, color: LinLinkColors.primary),
              ),
              const SizedBox(height: 16),
              const Text(
                'Remote Filesystem',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: LinLinkColors.onSurface),
              ),
              const SizedBox(height: 6),
              const Text(
                'Link with a Linux computer to browse directories, download files to your device, and upload local documents.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: LinLinkColors.onSurfaceVariant, height: 1.4),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: const Text('Pair Computer to Browse'),
                onPressed: widget.onRequestPair,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
