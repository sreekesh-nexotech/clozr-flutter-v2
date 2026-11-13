import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/config/api_config.dart';
import '../../application/providers/my_training_providers.dart';
import '../../domain/entities/my_course.dart';
import '../../infrastructure/data_sources/remote/my_training_remote_ds.dart';

/// Webapp `VideoPlayer`: the Bunny Stream embed driven through Player.js —
/// seeks to the saved position when ready, heartbeats `current_time` every
/// ~10 s while playing, reports `completed: true` on end, and flushes the
/// last position when the lesson is left.
class LmsVideoPlayer extends ConsumerStatefulWidget {
  const LmsVideoPlayer({
    super.key,
    required this.view,
    required this.enrollmentId,
    required this.onCompleted,
  });

  final VideoView view;
  final String enrollmentId;

  /// The server now counts this video complete (on end, or ≥ 95% watched).
  final VoidCallback onCompleted;

  @override
  ConsumerState<LmsVideoPlayer> createState() => _LmsVideoPlayerState();
}

class _LmsVideoPlayerState extends ConsumerState<LmsVideoPlayer> {
  static const _heartbeat = Duration(seconds: 10);

  late final WebViewController _controller;
  // Captured up front: `ref` must not be used from dispose().
  late final MyTrainingRemoteDataSource _remote =
      ref.read(myTrainingRemoteProvider);
  // Webapp: a completed answer refetches My Trainings and the course even when
  // it lands after the lesson was left (the end of a short clip often does).
  late final StateController<int> _refresh =
      ref.read(myTrainingRefreshProvider.notifier);
  late double _lastSeconds = widget.view.lastPlayedPosition;
  late bool _completed = widget.view.isCompleted;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _remote; // resolve while ref is live
    _refresh;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B1020))
      ..addJavaScriptChannel('Clozr',
          onMessageReceived: (m) => _onEvent(m.message))
      ..loadHtmlString(_html(), baseUrl: ApiConfig.baseUrl);
  }

  String _html() {
    final src = const HtmlEscape(HtmlEscapeMode.attribute)
        .convert(widget.view.videoUrl);
    final start =
        widget.view.lastPlayedPosition > 0 ? widget.view.lastPlayedPosition : 0;
    return '''<!doctype html><html><head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;height:100%;background:#0b1020;overflow:hidden}
iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0}</style>
<script src="https://cdn.jsdelivr.net/npm/player.js@0.1.0/dist/player-0.1.0.min.js"></script>
</head><body>
<iframe id="v" src="$src" allow="accelerometer; gyroscope; autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe>
<script>
function send(o){ try { Clozr.postMessage(JSON.stringify(o)); } catch (e) {} }
if (window.playerjs) {
  var p = new playerjs.Player(document.getElementById('v'));
  p.on('ready', function () { if ($start > 0) p.setCurrentTime($start); });
  p.on('timeupdate', function (d) { send({e: 'time', s: d.seconds}); });
  p.on('ended', function () { send({e: 'ended'}); });
}
</script></body></html>''';
  }

  void _onEvent(String raw) {
    final Object? msg;
    try {
      msg = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (msg is! Map || _completed) return;
    switch (msg['e']) {
      case 'time':
        final s = msg['s'];
        if (s is num) _lastSeconds = s.toDouble();
        final now = DateTime.now();
        if (now.difference(_lastSent) >= _heartbeat) {
          _lastSent = now;
          _report(completed: false);
        }
      case 'ended':
        _completed = true;
        _report(completed: true);
    }
  }

  Future<void> _report({required bool completed}) async {
    try {
      final done = await _remote.reportProgress(
        videoResourceId: widget.view.videoResourceId,
        enrollmentId: widget.enrollmentId,
        currentTime: _lastSeconds,
        completed: completed,
      );
      if (done) {
        _completed = true;
        if (mounted) {
          widget.onCompleted();
        } else {
          _refresh.state++;
        }
      }
    } on Object {
      // A missed heartbeat is re-sent on the next tick; a failed completion
      // is reported by the shell's failure toast.
    }
  }

  @override
  void dispose() {
    // Flush the last position (fire-and-forget) unless already complete.
    if (!_completed && _lastSeconds > 0) {
      _remote
          .reportProgress(
        videoResourceId: widget.view.videoResourceId,
        enrollmentId: widget.enrollmentId,
        currentTime: _lastSeconds,
        completed: false,
      )
          .then((done) {
        if (done) _refresh.state++;
      }).catchError((Object _) {});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: WebViewWidget(controller: _controller),
    );
  }
}
