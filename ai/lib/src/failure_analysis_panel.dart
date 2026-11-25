import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

import 'ai_request.dart';
import 'api_key_dialog.dart';
import 'api_key_store.dart';
import 'failure_analysis.dart';
import 'redact.dart';

/// 보내기 전 확인 창에 쓰는 분석 이름.
const failureAnalysisRequestName = '실행 실패 원인 분석';

/// 카드에 한 번 보여주는 설명. 패널이 혼자 쓰일 때(화면 6·오래된 프로젝트 점검)는 [FailureAnalysisPanel.description] 으로 넘긴다.
const failureAnalysisDescription =
    '실패한 항목의 로그와 마지막 성공 때와 달라진 환경을 AI가 읽고 원인 후보와 해결 방법을 찾아 줘요. 누를 때만 분석하고, 보내기 전에 보낼 내용을 먼저 보여 드려요.';

const _sendNote = '실행 설정은 명령·폴더·포트·준비 조건만 보내요. 환경변수와 .env 파일 내용은 보내지 않아요.';
const _caution = 'AI 결과는 틀릴 수 있어요. 근거(로그 줄, 검사 항목)를 확인한 뒤 판단해 주세요.';

/// AI-02 실행 실패 원인 분석 패널. 실패한 항목 하나를 분석한다.
///
/// 화면 8 카드에 쓰고, 나중에 화면 6(헬스체크, C)·오래된 프로젝트 점검(FR-17)에도 끼운다.
/// [logs]·[envDiff] 가 없으면(아직 앱에 등록 안 됨) 그 칸을 "못 읽음"으로 보내고 나머지로 분석한다.
class FailureAnalysisPanel extends StatefulWidget {
  const FailureAnalysisPanel({
    super.key,
    required this.item,
    required this.run,
    required this.client,
    required this.keys,
    required this.projects,
    this.logs,
    this.envDiff,
    this.description,
    this.checkKey,
    this.onKeysChanged,
  });

  /// 분석할 실패 항목.
  final ItemResult item;

  /// 그 항목이 실패한 전체 실행.
  final RunSummary run;
  final LlmClient client;
  final ApiKeyStore keys;

  /// 그 항목의 실행 설정을 읽는다.
  final ProjectRepository projects;
  final LogExcerpt? logs;
  final EnvDiff? envDiff;

  /// 처음·취소함 상태에 보여줄 설명. null 이면 [원인 분석]만.
  final String? description;
  final ApiKeyCheck? checkKey;
  final VoidCallback? onKeysChanged;

  @override
  State<FailureAnalysisPanel> createState() => _FailureAnalysisPanelState();
}

class _FailureAnalysisPanelState extends State<FailureAnalysisPanel> {
  /// 마지막으로 보낸 글의 입력. 답 읽기가 이 입력의 번호로 근거를 찾는다.
  FailureAnalysisInput? _input;

  /// 보낼 때마다 새로 모은다(로그를 그때 읽는다).
  Future<String> _content() async {
    final input = await FailureAnalysisInput.collect(
      item: widget.item,
      run: widget.run,
      projects: widget.projects,
      logs: widget.logs,
      envDiff: widget.envDiff,
    );
    _input = input;
    return input.prompt;
  }

  @override
  Widget build(BuildContext context) => AiRequestView<List<FailureCandidate>>(
        client: widget.client,
        keys: widget.keys,
        requestName: failureAnalysisRequestName,
        content: _content,
        parse: (reply) => parseFailureAnalysis(reply, _input!),
        done: (context, candidates, again) => _done(candidates, again),
        startLabel: '원인 분석',
        againLabel: '다시 분석',
        system: failureAnalysisSystem,
        notes: const [_sendNote],
        description: widget.description,
        checkKey: widget.checkKey,
        onKeysChanged: widget.onKeysChanged,
      );

  Widget _done(List<FailureCandidate> candidates, VoidCallback again) {
    const body = TextStyle(fontSize: 14, height: 1.6);
    const label = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.text2);
    const muted = TextStyle(fontSize: 13, color: C.muted, height: 1.6);
    final evidence = mono.copyWith(fontSize: 12, color: C.text2);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      for (final c in candidates)
        Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
          StatusChip('원인 후보 · ${likelihoodLabel(c.likelihood)}', c.likelihood == Likelihood.high ? C.warn : C.idle),
          Text(c.cause, style: body),
          if (c.logLines.isNotEmpty) ...[
            Text('근거 로그 · ${widget.item.item.serviceId} 마지막 실행', style: label),
            // 보낸 글은 AiSender 가 가렸다. 화면의 근거 줄도 같이 가린다(.env 값을 화면에 평문으로 두지 않는다).
            for (final line in c.logLines) Text(redactSecrets(line).text, style: evidence),
          ],
          for (final e in c.envChanges) Text('환경 차이 · ${envChangeLabel(e)}', style: label),
          if (c.reason) Text('실패 이유 · ${failureReasonText(widget.item)}', style: label),
          if (c.fixes.isNotEmpty) ...[
            const Text('해결 방법', style: label),
            for (final (i, fix) in c.fixes.indexed) Text('${i + 1}. $fix', style: body),
          ],
        ]),
      Text('분석 완료 · ${widget.client.modelName}', style: evidence),
      const Text(_caution, style: muted),
      Align(alignment: Alignment.centerRight, child: Btn('다시 분석', onPressed: again)),
    ]);
  }
}
