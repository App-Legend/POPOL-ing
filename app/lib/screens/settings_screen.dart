import 'dart:io';

import 'package:flutter/material.dart';

import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

/// 6. 프로젝트 설정. [ProjectRepository] 에서 프로젝트 메모 등을 읽고 저장한다(FR-15).
///
/// [projectId] 가 주어지면 해당 프로젝트를 읽고, 없으면 첫 번째 프로젝트를 읽는다.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.projectRepository,
    this.projectId,
  });

  final ProjectRepository projectRepository;
  final String? projectId;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _memoController = TextEditingController();
  bool _loading = true;
  Project? _project;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final projects = await widget.projectRepository.listProjects();
    final project = widget.projectId != null
        ? await widget.projectRepository.getProject(widget.projectId!)
        : projects.isNotEmpty ? projects.first : null;

    if (!mounted) return;
    setState(() {
      _project = project;
      _memoController.text = project?.about.memo ?? '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_project == null) return;

    final memo = _memoController.text.trim().isEmpty ? null : _memoController.text.trim();
    final updatedConfig = _project!.config == null
        ? ProjectConfig(about: About(memo: memo))
        : _project!.config!.copyWith(
            about: About(
              summary: _project!.about.summary,
              stack: _project!.about.stack,
              links: _project!.about.links,
              memo: memo,
            ),
          );
    final updated = _project!.copyWith(config: updatedConfig);

    try {
      await widget.projectRepository.updateProject(updated);
    } on FileSystemException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('저장하지 못했어요. 다른 프로그램이 popoling.yaml을 열고 있는지 확인해 주세요.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _project = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('메모를 저장했어요.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AppPage(crumbs: [('설정', null)], children: [Center(child: CircularProgressIndicator())]);
    }

    if (_project == null) {
      return const AppPage(
        crumbs: [('설정', null)],
        children: [Center(child: Text('프로젝트를 찾을 수 없어요.'))],
      );
    }

    return AppPage(
      crumbs: [('개발', '/home'), ('프로젝트 설정', null)],
      children: [
        PageHead(
          title: '프로젝트 설정',
          sub: _project!.folderPath,
          subMono: true,
          actions: [Btn('popoling.yaml 열기'), Btn('저장', primary: true, onPressed: _save)],
        ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Panel(
              title: '프로젝트 소개',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
                field('이름', _project!.name),
                field('한 줄 설명', _project!.about.summary ?? ''),
                field('기술 스택 (쉼표로 구분)', _project!.about.stack.join(', '), isMono: true),
                field('저장소 링크', _project!.about.links['repo'] ?? '', isMono: true),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 6,
                  children: [
                    const Text('메모', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    TextFormField(
                      controller: _memoController,
                      maxLines: 3,
                      style: const TextStyle(fontSize: 14),
                      decoration: _inputDeco,
                    ),
                  ],
                ),
                Text('처음 등록할 때 README 첫 문단과 Git 원격 주소로 채워졌어요.',
                    style: const TextStyle(fontSize: 12, color: C.muted)),
              ]),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(flex: 2, child: _services()),
        ]),
      ],
    );
  }

  Widget _services() {
    Widget svc(String name, Widget kind, Widget note) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.divider))),
          child: Row(spacing: 10, children: [Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w500))), kind, note]),
        );
    const muted13 = TextStyle(color: C.muted, fontSize: 13);

    return Panel(
      title: '실행 항목',
      titleAction: const Btn('항목 추가'),
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        svc('db', const Tag('Compose'), const Text('의존 없음', style: muted13)),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(color: C.headBg, border: Border(top: BorderSide(color: C.divider))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
            Row(spacing: 10, children: [
              const Expanded(child: Text('api', style: TextStyle(fontWeight: FontWeight.w700))),
              const Tag('프로세스'),
              Text('오류 1', style: TextStyle(color: C.bad.$2, fontSize: 13)),
            ]),
            AutoGrid(minItemWidth: 220, gap: 12, children: [
              dropdown('유형', ['프로세스', 'Docker Compose', '원격 연결']),
              field('작업 폴더', './backend', isMono: true),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
              const Text('명령과 인자 (한 칸에 하나씩 — 셸로 해석하지 않아요)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              Wrap(spacing: 8, children: [
                const Tag('./gradlew'),
                const Tag('bootRun'),
                ActionChip(label: const Text('+ 인자', style: TextStyle(fontSize: 12)), onPressed: () {}, visualDensity: VisualDensity.compact),
              ]),
            ]),
            AutoGrid(minItemWidth: 220, gap: 12, children: [
              field('환경변수', 'SPRING_PROFILES_ACTIVE=local', isMono: true),
              field('env 파일', './backend/.env', isMono: true),
              field('포트', '8080', isMono: true),
              Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
                const Text('의존 항목', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Checkbox(value: true, onChanged: (_) {}),
                  const Text('db'),
                  const SizedBox(width: 12),
                  Checkbox(value: true, onChanged: (_) {}),
                  Text('web (순환)', style: TextStyle(color: C.bad.$2)),
                ]),
              ]),
              dropdown('준비 조건', ['HTTP 응답', '포트 열림', '로그 패턴', 'Compose healthy', '없음']),
              field('준비 확인 URL', 'http://localhost:8080/actuator/health', isMono: true),
              field('준비 제한 시간 (초)', '120', isMono: true),
              field('종료 유예 (초)', '15', isMono: true),
            ]),
          ]),
        ),
        svc('web', const Tag('프로세스'), const Text('의존: api', style: muted13)),
        svc('storage', const Tag('원격 연결', tone: C.remote), Text('https://storage.my-team.dev/health', style: mono.copyWith(fontSize: 12, color: C.muted))),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.divider))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
            const Text('헬스체크 주소', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            AutoGrid(minItemWidth: 220, gap: 8, children: const [
              Text('프론트 메인 · http://localhost:5173', style: TextStyle(fontSize: 13)),
              Text('API 헬스 · …/actuator/health · 200', style: TextStyle(fontSize: 13)),
              Text('관리자 페이지 · 주소 없음', style: TextStyle(fontSize: 13, color: C.muted)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// 라벨 + 입력칸. 대화상자 화면도 같이 쓴다.
Widget field(String label, String value, {bool isMono = false, int lines = 1, String? hint, bool obscure = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Text.rich(TextSpan(style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), children: [
          TextSpan(text: label),
          if (hint != null) TextSpan(text: '  $hint', style: const TextStyle(fontWeight: FontWeight.w400, color: C.muted)),
        ])),
        TextFormField(
          initialValue: value,
          maxLines: lines,
          obscureText: obscure,
          style: isMono ? mono.copyWith(fontSize: 13) : const TextStyle(fontSize: 14),
          decoration: _inputDeco,
        ),
      ],
    );

Widget dropdown(String label, List<String> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        DropdownButtonFormField<String>(
          initialValue: items.first,
          isExpanded: true,
          decoration: _inputDeco,
          items: [for (final i in items) DropdownMenuItem(value: i, child: Text(i, style: const TextStyle(fontSize: 14)))],
          onChanged: (_) {},
        ),
      ],
    );

const _inputDeco = InputDecoration(
  isDense: true,
  filled: true,
  fillColor: C.surface,
  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  border: OutlineInputBorder(borderSide: BorderSide(color: C.borderStrong)),
  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: C.borderStrong)),
);
