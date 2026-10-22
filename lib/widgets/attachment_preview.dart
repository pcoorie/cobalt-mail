import 'dart:io';
import 'package:flutter/material.dart';

/// Widget to display a preview of an attachment with file type icon, name, and size.
class AttachmentPreview extends StatelessWidget {
  const AttachmentPreview({
    super.key,
    required this.filePath,
    required this.onRemove,
  });

  /// The path to the file
  final String filePath;

  /// Callback function when user wants to remove this attachment
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final File file = File(filePath);
    final fileName = file.path.split('/').last;
    final fileSize = file.lengthSync();
    
    // Determine file type icon based on extension
    String icon = '📎'; // Default generic attachment icon
    final extension = fileName.split('.').last.toLowerCase();
    
    switch (extension) {
      case 'pdf':
        icon = '📄';
        break;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        icon = '🖼️';
        break;
      case 'doc':
      case 'docx':
        icon = '📝';
        break;
      case 'zip':
      case 'rar':
      case 'tar':
        icon = '📦';
        break;
      default:
        // Keep default for other file types
        break;
    }
    
    // Format file size for display
    String formatFileSize(int bytes) {
      if (bytes < 1024) return '$bytes B';
      if (bytes < (1024 * 1024)) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      if (bytes < (1024 * 1024 * 1024)) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    
    final formattedSize = formatFileSize(fileSize);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  formattedSize,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}