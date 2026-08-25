import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/api_config.dart';

/// Opening a stored attachment.
///
/// An attachment row carries whatever the backend put in its `file` field,
/// which is either an absolute link (S3 / CDN) or a media path relative to the
/// API origin (`/media/attachments/…`). Both have to end up as something the
/// platform can hand to a browser or a document viewer, which is what
/// [attachmentUri] is for.

/// The absolute link for a stored attachment, or `null` when the row carries
/// nothing usable.
///
/// A relative path is resolved against [ApiConfig.baseUrl] — the media host is
/// the API origin, not the `/api/v1` prefix, so the prefix is deliberately not
/// part of this.
Uri? attachmentUri(String url) {
  final raw = url.trim();
  if (raw.isEmpty) return null;

  final parsed = Uri.tryParse(raw);
  if (parsed == null) return null;
  if (parsed.hasScheme) return parsed;

  final base = Uri.tryParse(ApiConfig.baseUrl);
  if (base == null || !base.hasScheme) return null;
  return base.resolveUri(parsed);
}

/// A glyph for the file's kind, so an attachment row reads before its name
/// does. Shared by every Files list (lead, task, follow-up) so the same
/// extension never draws as two different things.
IconData attachmentIcon(String ext) => switch (ext.toUpperCase()) {
      'PNG' || 'JPG' || 'JPEG' || 'GIF' || 'WEBP' || 'HEIC' =>
        PhosphorIconsRegular.image,
      'PDF' => PhosphorIconsRegular.filePdf,
      'DOC' || 'DOCX' || 'RTF' || 'TXT' => PhosphorIconsRegular.fileText,
      'XLS' || 'XLSX' || 'CSV' => PhosphorIconsRegular.fileXls,
      'ZIP' || 'RAR' || '7Z' => PhosphorIconsRegular.fileZip,
      'MP4' || 'MOV' || 'AVI' => PhosphorIconsRegular.filmSlate,
      _ => PhosphorIconsRegular.paperclip,
    };

/// Hands [url] to the platform (browser / document viewer).
///
/// Returns `null` when the file was handed over, or a message to show the user
/// when it could not be. Failure is reported rather than thrown so a dead link
/// on one row never takes the screen down.
Future<String?> openAttachment(String url) async {
  final uri = attachmentUri(url);
  if (uri == null) return 'This file has no link to open.';
  try {
    // `externalApplication` puts a PDF or an image in front of the OS viewer
    // instead of an in-app web view, which is what "view the file" means here.
    // Some hosts (and the Android emulator without a browser) reject that mode,
    // so the platform default is tried before giving up.
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication) ||
        await launchUrl(uri);
    return opened ? null : 'No app on this device can open this file.';
  } on Object catch (e) {
    return 'Could not open this file: $e';
  }
}
