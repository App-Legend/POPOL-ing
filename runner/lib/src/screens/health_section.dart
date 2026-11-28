import 'dart:async';

import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/fakes.dart';
import 'package:popoling_core/ui.dart';

/// 로그 탭 아래 헬스체크(FR-10, 목업 v2 3번). [QaRunner] 계약만으로 그린다.
///
/// 진짜 QaRunner 가 아직 없어 가짜면 "샘플" 라벨을 붙인다(가짜 결과가 진짜처럼 보이지 않게).
class HealthSection extends StatefulWidget {
  const HealthSection({super.key, required this.projectId, required this.qa, this.summary});

  final String projectId;
  final QaRunner qa;

  /// 결과 아래 [AI 요약] 자리. 없으면 숨긴다.
  final Widget Function(BuildContext context, QaRun run)? summary;

  @override
  State<HealthSection> createState() => _HealthSectionState();
}

class _HealthSectionState extends State<HealthSection> {
  QaRun? _run;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.qa.history(widget.projectId).then((h) {
      if (mounted && _run == null && h.isNotEmpty) setState(() => _run = h.first);
    }, onError: (_) {}); // 이력을 못 읽으면 빈 상태로 둔다
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final run = await widget.qa.runChecks(widget.projectId);
      if (mounted) setState(() => _run = run);
    } catch (_) {
      if (mounted) setState(() => _error = '헬스체크를 하지 못했어요');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final run = _run;
    final failed = run?.results.where((r) => r.status == QaStatus.failed).length ?? 0;
    return Panel(
      title: '헬스체크',
      titleAction: run == null ? null : (failed > 0 ? StatusChip('실패 $failed', C.bad) : const StatusChip('모두 통과', C.ok)),
      subtitle: run == null ? '적어 둔 주소가 지금 응답하는지 확인해요' : '적어 둔 주소가 지금 응답하는지 확인해요 · ${_time(run.startedAt)}',
      actions: [
        if (widget.qa is FakeQaRunner) const StatusChip('샘플 · 진짜 검사 기능이 아직 없어요', C.idle, dot: false),
        Btn('다시 검사', small: true, onPressed: _busy ? null : _check),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        if (_error != null) Text(_error!, style: TextStyle(fontSize: 14, color: C.bad.$2)),
        if (run == null)
          const Text('아직 헬스체크 결과가 없어요.', style: TextStyle(fontSize: 14))
        else
          SimpleTable(
            minWidth: 560,
            columns: const ['결과', '검사', '응답', '걸린 시간'],
            rows: [
              for (final r in run.results)
                [
                  switch (r.status) {
                    QaStatus.passed => const StatusChip('통과', C.ok),
                    QaStatus.failed => const StatusChip('실패', C.bad),
                    QaStatus.needsSetup => const StatusChip('설정 필요', C.idle),
                  },
                  Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                    Text(r.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                    if (r.target != null) Text(r.target!, style: mono.copyWith(fontSize: 12, color: C.muted)),
                    if (r.failureReason != null) Text(r.failureReason!, style: TextStyle(fontSize: 12, color: C.bad.$2)),
                  ]),
                  Text(r.statusCode?.toString() ?? (r.status == QaStatus.failed ? '응답 없음' : '—')),
                  Text(r.elapsed == null ? '—' : '${r.elapsed!.inMilliseconds}ms'),
                ],
            ],
          ),
        if (run != null && widget.summary != null) widget.summary!(context, run),
      ]),
    );
  }

  static String _time(DateTime t) => '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
