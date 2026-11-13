import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/training/infrastructure/data_sources/remote/course_editor_remote_ds.dart';

void main() {
  test('moveId moves one step and refuses the ends (webapp moveId)', () {
    expect(moveId(['a', 'b', 'c'], 1, -1), ['b', 'a', 'c']);
    expect(moveId(['a', 'b', 'c'], 0, 1), ['b', 'a', 'c']);
    expect(moveId(['a', 'b', 'c'], 0, -1), isNull);
    expect(moveId(['a', 'b', 'c'], 2, 1), isNull);
  });

  test('deadline is sent as midnight UTC, or null', () {
    expect(deadlineWire(DateTime(2026, 10, 31)), '2026-10-31T00:00:00Z');
    expect(deadlineWire(null), isNull);
  });

  test('the course detail maps modules, videos, resources and roles', () {
    final c = EditorCourse.fromJson({
      'course_id': 'c1',
      'title': 'T',
      'status': 'published',
      'is_universal': true,
      'deadline': '2026-10-31T05:30:00+05:30',
      'assigned_to_roles': [
        {'role_id': null, 'name': 'all'},
      ],
      'pending_thumbnail_url': 'p.jpg',
      'modules': [
        {
          'module_id': 'm1',
          'title': 'Basics',
          'video_resources': [
            {
              'video_resource_id': 'v1',
              'title': 'A',
              'bunny_video_id': 'b1',
              'is_encoded': false,
              'encoding_failed': false
            },
            {
              'video_resource_id': 'v2',
              'title': 'B',
              'bunny_video_id': 'b2',
              'is_encoded': false,
              'encoding_failed': true
            },
          ],
          'resources': [
            {'module_resource_id': 'r1', 'title': 'Handout.pdf'},
          ],
        },
      ],
    });
    expect(c.isPublished, isTrue);
    expect(c.roleIds, isEmpty);
    expect(c.hasAssignedRoles, isTrue);
    expect(c.deadline, DateTime(2026, 10, 31));
    expect(c.modules.single.videos.first.isProcessing, isTrue);
    expect(c.modules.single.videos.last.isProcessing, isFalse);
    expect(c.modules.single.resources.single.title, 'Handout.pdf');
    expect(c.pendingThumbnailUrl, 'p.jpg');
  });
}
