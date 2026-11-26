import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

import '../file_project_repository.dart';

/// 프로젝트 화면 설정 탭(목업 v2 6번). 지금은 읽기 전용: 편집·저장은 PR #76 이 합쳐진 뒤 B 가 연결한다.
///
/// `.env` 파일은 이름만 보여 주고 내용은 읽지 않는다.
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key, required this.projectId, required this.projects});

  final String projectId;
  final ProjectRepository projects;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  Project? _project;
  String? _error;
  String? _open;

  @override
  void initState() {
    super.initState();
    widget.projects.getProject(widget.projectId).then((p) {
      if (mounted) setState(() => _project = p);
    }, onError: (Object e) {
      if (mounted) setState(() => _error = e is PopolingException ? e.message : '설정을 읽지 못했어요.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _project;
    if (p == null) return _error == null ? const LinearProgressIndicator() : Text(_error!, style: const TextStyle(color: C.muted));
    final config = p.config;
    final about = p.about;
    String orNone(String? v) => v == null || v.isEmpty ? '아직 없어요' : v;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      if (p.configIssues.isNotEmpty)
        Notice(
          bg: C.bad.$1,
          border: C.bad.$1,
          icon: Icons.error_outline,
          iconColor: C.bad.$2,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
            Text('설정 파일에 고칠 곳이 ${p.configIssues.length}개 있어요', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.bad.$2)),
            for (final i in p.configIssues)
              Text(i.path.isEmpty ? i.message : '${i.path}: ${i.message}', style: TextStyle(fontSize: 13, color: C.bad.$2)),
          ]),
        ),
      Panel(
        title: '소개·메모',
        child: KeyValues([
          ('한 줄 설명', Text(orNone(about.summary))),
          ('기술', Text(about.stack.isEmpty ? '아직 없어요' : about.stack.join(', '))),
          ('저장소', Text(orNone(about.links['repo']))),
          ('메모', Text(orNone(about.memo))),
          ('설정 파일', Text('${p.folderPath}/${FileProjectRepository.configFileName}', style: mono.copyWith(fontSize: 13))),
        ]),
      ),
      if (config == null || config.services.isEmpty)
        const Panel(title: '실행 항목', child: Text('실행 방법이 아직 없어요', style: TextStyle(fontSize: 14)))
      else
        Panel(
          title: '실행 항목 · ${config.services.length}',
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, s) in config.services.indexed) _serviceRow(i, s),
          ]),
        ),
      if (config != null && config.requires.isNotEmpty)
        Panel(
          title: '필요한 도구',
          child: SimpleTable(
            minWidth: 400,
            columns: const ['도구', '필요 버전'],
            rows: [
              for (final r in config.requires)
                switch (r) {
                  CliRequirement(:final cli, :final version) => [Text(cli, style: mono), Text(version ?? '설치돼 있으면 돼요')],
                  DockerRequirement() => [Text('Docker', style: mono), const Text('켜져 있어야 해요')],
                },
            ],
          ),
        ),
    ]);
  }

  Widget _serviceRow(int index, ServiceConfig s) {
    final open = _open == s.id;
    final (kind, command, port) = switch (s) {
      ProcessService(:final command, :final ports) => ('프로세스', command.join(' '), ports.isEmpty ? '—' : ports.join(', ')),
      ComposeService(:final file, :final services) => ('Compose', [file, ...services].join(' · '), '—'),
      RemoteService(:final ready) => ('원격', _readyTarget(ready), '—'),
    };
    final order = s is RemoteService
        ? '연결만 확인'
        : s.dependsOn.isEmpty
            ? '${index + 1} · 가장 먼저'
            : '${index + 1} · ${s.dependsOn.join(', ')} 다음';
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.divider))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => _open = open ? null : s.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(spacing: 12, children: [
              SizedBox(width: 110, child: Text(s.id, style: const TextStyle(fontWeight: FontWeight.w600))),
              SizedBox(width: 80, child: Text(kind, style: const TextStyle(color: C.text2))),
              Expanded(child: Text(command, style: mono.copyWith(fontSize: 13), overflow: TextOverflow.ellipsis)),
              SizedBox(width: 70, child: Text(port, style: mono.copyWith(fontSize: 13))),
              SizedBox(width: 130, child: Text(order, style: const TextStyle(fontSize: 13, color: C.text2))),
              Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: C.muted),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: KeyValues([
              if (s case ProcessService(:final cwd, :final envFile, :final stopTimeout)) ...[
                ('실행할 폴더', Text(cwd, style: mono)),
                if (envFile != null) ('비밀값 파일', Text(envFile, style: mono)),
                ('중지 대기', Text('${stopTimeout.inSeconds}초')),
              ],
              ('먼저 시작할 항목', Text(s.dependsOn.isEmpty ? '없음' : s.dependsOn.join(', '))),
              ('준비 확인', Text(_readyText(s.ready))),
            ]),
          ),
      ]),
    );
  }

  static String _readyTarget(ReadyCondition r) => switch (r) {
        HttpReady(:final url) => url,
        PortReady(:final host, :final port) => '${host ?? 'localhost'}:$port',
        _ => '—',
      };

  static String _readyText(ReadyCondition r) {
    final what = switch (r) {
      PortReady(:final host, :final port) => '포트 ${host ?? 'localhost'}:$port 열림',
      HttpReady(:final url) => '주소 응답 · $url',
      LogReady(:final pattern) => '로그에 "$pattern"',
      ComposeHealthyReady() => 'Compose healthcheck',
      NoneReady() => '시작하면 바로 준비 완료',
    };
    return r is NoneReady ? what : '$what · 최대 ${r.timeout.inSeconds}초';
  }
}
