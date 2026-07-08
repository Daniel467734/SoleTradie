import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// Full-screen attachment viewer with swipe navigation between photos
class AttachmentViewerScreen extends StatefulWidget {
  final List<String> attachmentPaths;
  final int initialIndex;

  const AttachmentViewerScreen({
    Key? key,
    required this.attachmentPaths,
    this.initialIndex = 0,
  }) : super(key: key);

  @override
  State<AttachmentViewerScreen> createState() => _AttachmentViewerScreenState();
}

class _AttachmentViewerScreenState extends State<AttachmentViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _getFileName(String path) {
    return path.split('/').last;
  }

  bool _isImageFile(String path) {
    final imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
    return imageExtensions.contains(path.split('.').last.toLowerCase());
  }

  bool _isPdfFile(String path) {
    return path.split('.').last.toLowerCase() == 'pdf';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_currentIndex + 1} / ${widget.attachmentPaths.length}'),
        centerTitle: true,
        elevation: 0,
      ),
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemCount: widget.attachmentPaths.length,
        itemBuilder: (context, index) {
          final filePath = widget.attachmentPaths[index];
          final fileName = _getFileName(filePath);
          final isImage = _isImageFile(filePath);
          final isPdf = _isPdfFile(filePath);

          return Column(
            children: [
              Expanded(
                child: isPdf
                    ? _buildPdfView(filePath)
                    : GestureDetector(
                        onTap: () {
                          // Optional: hide/show UI on tap
                        },
                        child: Center(
                          child: isImage
                              ? _buildImageView(filePath, fileName)
                              : _buildFileView(fileName),
                        ),
                      ),
              ),
              // Bottom info bar
              Container(
                color: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fileName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      filePath,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Renders an actual PDF preview (all pages, pinch-to-zoom, scrollable)
  /// using the `printing` package's PdfPreview widget, reading the raw
  /// bytes from disk. Falls back to a simple error placeholder if the file
  /// can't be read/rendered (e.g. corrupted or missing file).
  Widget _buildPdfView(String filePath) {
    return Container(
      color: Colors.white,
      child: PdfPreview(
        build: (format) => File(filePath).readAsBytes(),
        canChangePageFormat: false,
        canChangeOrientation: false,
        allowPrinting: false,
        allowSharing: false,
        loadingWidget: const Center(
          child: CircularProgressIndicator(),
        ),
        onError: (context, error) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.picture_as_pdf,
                color: Colors.grey,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load PDF',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageView(String filePath, String fileName) {
    return InteractiveViewer(
      panEnabled: true,
      minScale: 1.0,
      maxScale: 4.0,
      child: Image.file(
        File(filePath),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.broken_image,
                  color: Colors.grey,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  'Failed to load image',
                  style: TextStyle(color: Colors.grey[400]),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFileView(String fileName) {
    final extension = fileName.split('.').last.toUpperCase();
    
    IconData iconData;
    switch (extension.toLowerCase()) {
      case 'pdf':
        iconData = Icons.picture_as_pdf;
        break;
      case 'doc':
      case 'docx':
        iconData = Icons.description;
        break;
      case 'xls':
      case 'xlsx':
        iconData = Icons.table_chart;
        break;
      default:
        iconData = Icons.insert_drive_file;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            iconData,
            size: 96,
            color: Colors.grey,
          ),
          const SizedBox(height: 24),
          Text(
            '$extension File',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            fileName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 14,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 24),
          Text(
            'Swipe left or right to view other attachments',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders a small thumbnail image of the first page of a PDF file, for use
/// in lists (e.g. the Attachments list in JobDetailsScreen) so PDFs get a
/// visual preview instead of just a generic file icon. Falls back to a
/// simple PDF icon if rendering fails (e.g. corrupted file).
class PdfThumbnail extends StatefulWidget {
  final String filePath;
  final double width;
  final double height;

  const PdfThumbnail({
    super.key,
    required this.filePath,
    this.width = 40,
    this.height = 40,
  });

  @override
  State<PdfThumbnail> createState() => _PdfThumbnailState();
}

class _PdfThumbnailState extends State<PdfThumbnail> {
  Uint8List? _thumbnailBytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _renderThumbnail();
  }

  @override
  void didUpdateWidget(PdfThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _thumbnailBytes = null;
      _failed = false;
      _renderThumbnail();
    }
  }

  Future<void> _renderThumbnail() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        if (mounted) setState(() => _failed = true);
        return;
      }
      final bytes = await file.readAsBytes();
      final page = await Printing.raster(bytes, pages: [0], dpi: 72).first;
      final png = await page.toPng();
      if (mounted) {
        setState(() {
          _thumbnailBytes = png;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_thumbnailBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(
          _thumbnailBytes!,
          width: widget.width,
          height: widget.height,
          fit: BoxFit.cover,
        ),
      );
    }

    if (_failed) {
      return Icon(
        Icons.picture_as_pdf,
        size: widget.width,
        color: Colors.red[300],
      );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
