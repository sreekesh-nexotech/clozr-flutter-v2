import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../../../../core/network/api_service.dart';

/// A lesson video inside a module, as the course editor needs it.
class EditorVideo {
  const EditorVideo({
    required this.id,
    required this.title,
    required this.bunnyVideoId,
    required this.isEncoded,
    required this.encodingFailed,
  });

  final String id;
  final String title;
  final String bunnyVideoId;
  final bool isEncoded;
  final bool encodingFailed;

  bool get isProcessing =>
      !isEncoded && !encodingFailed && bunnyVideoId.isNotEmpty;
}

/// A PDF attached to a module.
class EditorResource {
  const EditorResource({required this.id, required this.title});
  final String id;
  final String title;
}

class EditorModule {
  const EditorModule(
      {required this.id,
      required this.title,
      required this.videos,
      required this.resources});
  final String id;
  final String title;
  final List<EditorVideo> videos;
  final List<EditorResource> resources;
}

/// `GET /lms/courses/{id}/` in the shape the editor edits.
class EditorCourse {
  const EditorCourse({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.isSequential,
    required this.isMandatory,
    required this.isUniversal,
    required this.isGlobal,
    required this.roleIds,
    required this.hasAssignedRoles,
    required this.deadline,
    required this.thumbnailUrl,
    required this.pendingThumbnailUrl,
    required this.modules,
  });

  final String id;
  final String title;
  final String description;
  final String status;
  final bool isSequential;
  final bool isMandatory;
  final bool isUniversal;
  final bool isGlobal;

  /// Real role ids (the `all` pseudo-role excluded).
  final List<String> roleIds;

  /// Any `assigned_to_roles` entry, the `all` pseudo-role included — what the
  /// webapp checks before offering "Keep current roles".
  final bool hasAssignedRoles;

  /// Date only (`YYYY-MM-DD`), or null for no deadline.
  final DateTime? deadline;
  final String thumbnailUrl;
  final String pendingThumbnailUrl;
  final List<EditorModule> modules;

  bool get isPublished => status == 'published';
  List<EditorVideo> get videos => [for (final m in modules) ...m.videos];

  static String _s(Object? v) => v is String ? v : '';

  static EditorCourse fromJson(Map<String, dynamic> j) {
    final roles = j['assigned_to_roles'];
    final mods = j['modules'];
    final dl = _s(j['deadline']);
    return EditorCourse(
      id: _s(j['course_id']),
      title: _s(j['title']),
      description: _s(j['description']),
      status: _s(j['status']),
      isSequential: j['is_sequential'] == true,
      isMandatory: j['is_mandatory'] == true,
      isUniversal: j['is_universal'] == true,
      isGlobal: j['is_global'] == true,
      roleIds: [
        if (roles is List)
          for (final r in roles)
            if (r is Map && r['role_id'] is String) r['role_id'] as String,
      ],
      hasAssignedRoles: roles is List && roles.isNotEmpty,
      deadline: dl.length >= 10 ? DateTime.tryParse(dl.substring(0, 10)) : null,
      thumbnailUrl: _s(j['thumbnail_url']),
      pendingThumbnailUrl: _s(j['pending_thumbnail_url']),
      modules: [
        if (mods is List)
          for (final m in mods)
            if (m is Map && m['module_id'] is String)
              EditorModule(
                id: m['module_id'] as String,
                title: _s(m['title']),
                videos: [
                  if (m['video_resources'] is List)
                    for (final v in m['video_resources'] as List)
                      if (v is Map && v['video_resource_id'] is String)
                        EditorVideo(
                          id: v['video_resource_id'] as String,
                          title: _s(v['title']),
                          bunnyVideoId: _s(v['bunny_video_id']),
                          isEncoded: v['is_encoded'] == true,
                          encodingFailed: v['encoding_failed'] == true,
                        ),
                ],
                resources: [
                  if (m['resources'] is List)
                    for (final r in m['resources'] as List)
                      if (r is Map && r['module_resource_id'] is String)
                        EditorResource(
                            id: r['module_resource_id'] as String,
                            title: _s(r['title'])),
                ],
              ),
      ],
    );
  }
}

/// `YYYY-MM-DDT00:00:00Z` (the webapp's deadline wire format), or null.
String? deadlineWire(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}T00:00:00Z';

/// Every course-editor call the webapp makes (course, modules, videos via a
/// direct TUS upload to Bunny Stream, PDF resources, staged thumbnail).
class CourseEditorRemoteDataSource {
  CourseEditorRemoteDataSource(this._api, {Dio? bunny})
      : _bunny = bunny ?? Dio();

  final ApiService _api;

  /// A plain client for Bunny's TUS endpoint — Bunny authenticates with the
  /// server-minted signature headers, never with the Clozr session.
  final Dio _bunny;

  static const bunnyTusEndpoint = 'https://video.bunnycdn.com/tusupload';
  static const _chunk = 5 * 1024 * 1024;

  static String _course(String id) => '/lms/courses/$id/';
  static String _modules(String courseId) => '/lms/courses/$courseId/modules/';

  Future<EditorCourse> fetchCourse(String id) async => EditorCourse.fromJson(
      Map<String, dynamic>.from(await _api.get(_course(id)) as Map));

  /// Returns the new course id.
  Future<String> createCourse({
    required String title,
    required bool isSequential,
    required bool isMandatory,
    DateTime? deadline,
  }) async {
    final body = await _api.post('/lms/courses/', body: {
      'title': title,
      'description': '',
      'status': 'draft',
      'is_sequential': isSequential,
      'is_mandatory': isMandatory,
      'deadline': deadlineWire(deadline),
      'assigned_to_role_ids': <String>[],
    });
    return body is Map && body['course_id'] is String
        ? body['course_id'] as String
        : '';
  }

  Future<void> updateCourse(String id, Map<String, dynamic> patch) =>
      _api.patch(_course(id), body: patch);

  /// Commits a staged thumbnail (a no-op when nothing is staged).
  Future<void> saveCourse(String id) => _api.post('${_course(id)}save/');
  Future<void> publish(String id) => _api.post('${_course(id)}publish/');
  Future<void> draft(String id) => _api.post('${_course(id)}draft/');

  Future<String> addModule(String courseId, int position) async {
    final body = await _api.post(_modules(courseId),
        body: {'title': 'New module', 'description': '', 'position': position});
    return body is Map && body['module_id'] is String
        ? body['module_id'] as String
        : '';
  }

  Future<void> renameModule(String courseId, String moduleId, String title) =>
      _api.patch('${_modules(courseId)}$moduleId/', body: {'title': title});

  Future<void> deleteModule(String courseId, String moduleId) =>
      _api.delete('${_modules(courseId)}$moduleId/');

  Future<void> reorderModules(String courseId, List<String> ids) =>
      _api.post('${_modules(courseId)}reorder/', body: {'module_ids': ids});

  Future<void> reorderVideos(String moduleId, List<String> ids) =>
      _api.post('/lms/modules/$moduleId/video-resources/reorder/',
          body: {'video_resource_ids': ids});

  Future<void> deleteVideo(String videoResourceId) =>
      _api.delete('/lms/video-resources/$videoResourceId/');

  /// Bunny encoding status (3 transcoding, 4 finished, 5 error, 6 upload
  /// failed). The server saves what it reads, so a settled status means the
  /// course detail now carries the final flags.
  Future<int> streamStatus(String bunnyVideoId) async {
    final body =
        await _api.get('/lms/stream/status/$bunnyVideoId/', quiet: true);
    final s = body is Map ? body['status'] : null;
    return s is num ? s.toInt() : 0;
  }

  /// Webapp `useVideoUpload`: mint upload credentials → TUS upload straight to
  /// Bunny → attach to the module. [onStep] reports `requesting`, `uploading`
  /// (with [onProgress] 0–100) and `attaching`.
  Future<void> uploadVideo({
    required String moduleId,
    required File file,
    required String title,
    required int position,
    required void Function(String step) onStep,
    required void Function(int percent) onProgress,
    CancelToken? cancel,
  }) async {
    onStep('requesting');
    final creds =
        await _api.post('/lms/stream/upload-url/', body: {'title': title});
    if (creds is! Map)
      throw const FormatException('The upload could not be prepared.');
    final videoId = '${creds['video_id']}';
    final headers = {
      'AuthorizationSignature': '${creds['signature']}',
      'AuthorizationExpire': '${creds['expiration']}',
      'VideoId': videoId,
      'LibraryId': '${creds['library_id']}',
      'Tus-Resumable': '1.0.0',
    };
    final size = await file.length();
    final ext = file.path.split('.').last.toLowerCase();
    final type = switch (ext) {
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      _ => 'video/mp4'
    };
    String b64(String s) => base64.encode(utf8.encode(s));

    onStep('uploading');
    onProgress(0);
    final created = await _bunny.post<dynamic>(
      bunnyTusEndpoint,
      options: Options(headers: {
        ...headers,
        'Upload-Length': '$size',
        'Upload-Metadata': 'filetype ${b64(type)},title ${b64(title)}',
      }),
      cancelToken: cancel,
    );
    var location = created.headers.value('location') ?? '';
    if (location.isEmpty)
      throw const FormatException(
          'The video service did not accept the upload.');
    if (location.startsWith('/'))
      location = 'https://video.bunnycdn.com$location';

    final raf = await file.open();
    try {
      var offset = 0;
      while (offset < size) {
        final len = (size - offset) < _chunk ? size - offset : _chunk;
        await raf.setPosition(offset);
        final bytes = await raf.read(len);
        final start = offset;
        await _bunny.patch<dynamic>(
          location,
          data: Stream.fromIterable([bytes]),
          options: Options(headers: {
            ...headers,
            'Upload-Offset': '$offset',
            'Content-Type': 'application/offset+octet-stream',
            Headers.contentLengthHeader: bytes.length,
          }),
          cancelToken: cancel,
          onSendProgress: (sent, _) =>
              onProgress(((start + sent) * 100 / size).floor().clamp(0, 100)),
        );
        offset += bytes.length;
      }
    } finally {
      await raf.close();
    }
    onProgress(100);

    onStep('attaching');
    await _api.post('/lms/modules/$moduleId/video-resources/', body: {
      'title': title,
      'bunny_video_id': videoId,
      'position': position,
      'duration_seconds': 0,
      'summary': '',
    });
  }

  /// Upload a PDF, then attach it to the module.
  Future<void> attachPdf(String moduleId, File file) async {
    final name = file.path.split(Platform.pathSeparator).last;
    final up = await _api.postForm(
        '/lms/resources/upload/',
        FormData.fromMap({
          'file': await MultipartFile.fromFile(file.path,
              filename: name, contentType: DioMediaType('application', 'pdf'))
        }));
    if (up is! Map)
      throw const FormatException('The file could not be uploaded.');
    final fileName =
        up['file_name'] is String && (up['file_name'] as String).isNotEmpty
            ? up['file_name'] as String
            : name;
    await _api.post('/lms/modules/$moduleId/resources/', body: {
      'title': fileName,
      'file_url': up['file_url'],
      'storage_path': up['storage_path'],
      'file_type': 'pdf',
      'file_size_bytes': up['file_size_bytes'],
    });
  }

  Future<void> deleteResource(String moduleResourceId) =>
      _api.delete('/lms/module-resources/$moduleResourceId/');

  /// Stages a thumbnail; it goes live on the next [saveCourse].
  Future<void> stageThumbnail(String courseId, File file) async {
    final name = file.path.split(Platform.pathSeparator).last;
    final ext = name.split('.').last.toLowerCase();
    final sub = switch (ext) {
      'png' => 'png',
      'webp' => 'webp',
      'gif' => 'gif',
      _ => 'jpeg'
    };
    await _api.postForm(
        '${_course(courseId)}thumbnail/',
        FormData.fromMap({
          'thumbnail': await MultipartFile.fromFile(file.path,
              filename: name, contentType: DioMediaType('image', sub))
        }));
  }
}

/// Webapp `moveId`: the id list with [index] moved one step, or null at an end.
List<String>? moveId(List<String> ids, int index, int direction) {
  final to = index + direction;
  if (index < 0 || index >= ids.length || to < 0 || to >= ids.length)
    return null;
  final next = [...ids];
  final id = next.removeAt(index);
  next.insert(to, id);
  return next;
}
