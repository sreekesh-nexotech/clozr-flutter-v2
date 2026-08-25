import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import '../models/note.dart';
import '../utils/attachment_link.dart';

/// Full-screen preview for a stored attachment.
///
/// An attachment chip used to do one thing: hand its link to the OS. That is
/// fine for a PDF, but for a photo it meant leaving the app to see something
/// the app could show — and on a device with no browser, nothing happened at
/// all. Images now open here; everything else still goes to the OS viewer,
/// which is the only thing that can render it.
///
/// The files are served from the CDN as ordinary public https links, so no auth
/// header is needed to load one.
Future<void> showAttachmentPreview(
  BuildContext context,
  NoteAttachment attachment, {
  required Future<void> Function() onOpenExternally,
}) {
  final image = attachmentImage(attachment);
  if (image == null) return Future.value();
  return Navigator.of(context).push<void>(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) => _AttachmentPreview(
        image: image,
        name: attachment.name,
        // A picked file is not on a server yet, so there is no link to hand
        // the OS — the header action is dropped rather than shown dead.
        onOpenExternally: attachment.url == null || attachment.url!.isEmpty
            ? null
            : onOpenExternally,
      ),
    ),
  );
}

/// The image behind an attachment, or null when it is not one we can render.
///
/// A **picked** file is read from disk, so a photo can be checked before the
/// note is posted — it used to show a filename chip and nothing else, and the
/// only way to see what you had attached was to send it.
ImageProvider? attachmentImage(NoteAttachment a) {
  if (!a.isImage) return null;
  final local = a.localPath;
  if (local != null && local.isNotEmpty) return FileImage(File(local));
  final uri = attachmentUri(a.url ?? '');
  return uri == null ? null : NetworkImage(uri.toString());
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({
    required this.image,
    required this.name,
    this.onOpenExternally,
  });

  final ImageProvider image;
  final String name;
  final Future<void> Function()? onOpenExternally;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(8.w, 4.h, 8.w, 4.h),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(PhosphorIconsBold.x, size: 20.sp, color: AppColors.white),
                  ),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(
                          size: 14, weight: FontWeight.w700, color: AppColors.white),
                    ),
                  ),
                  // Downloading is the browser's job — the app ships no file
                  // storage plugin, and a browser save is the platform's own
                  // download flow rather than a second one bolted on.
                  if (onOpenExternally case final open?)
                    IconButton(
                      tooltip: 'Open or download',
                      onPressed: open,
                      icon: Icon(PhosphorIconsBold.downloadSimple,
                          size: 20.sp, color: AppColors.white),
                    ),
                ],
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Image(
                    image: image,
                    fit: BoxFit.contain,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : const Center(
                            child: CircularProgressIndicator(color: AppColors.white)),
                    // A dead link is said out loud, with the OS viewer still
                    // offered — the file may open where the image decoder failed.
                    errorBuilder: (_, __, ___) => Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32.w),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsRegular.imageBroken,
                              size: 34.sp, color: AppColors.white),
                          SizedBox(height: 10.h),
                          Text(
                            "This image couldn't be loaded.",
                            textAlign: TextAlign.center,
                            style: AppText.custom(
                                size: 13, weight: FontWeight.w600, color: AppColors.white),
                          ),
                          SizedBox(height: 12.h),
                          if (onOpenExternally case final open?)
                            TextButton(
                              onPressed: open,
                              child: Text('Open in browser',
                                style: AppText.custom(
                                    size: 13,
                                    weight: FontWeight.w700,
                                    color: AppColors.blueBright)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
