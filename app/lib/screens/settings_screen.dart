import 'dart:io';

import 'package:flutter/material.dart';

import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

/// 6. 프로젝트 설정. [projectId] 로 프로젝트를 찾아 ppoling.yaml 설정을 보여준다.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.projectId});
  final String projectId;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Project? _project;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final project = await RegistryHolder.of(context).read<ProjectRepository>().getProject(widget.projectId);
      if (!mounted) return;
      setState(() {
        _project = project;
        _loading = false;
      });
    } on PpolingException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final project = _project;
    if (project == null) return;
    final config = project.config;
    if (config == null) {
      if (!mounted) return;
      setState(() => _error = '설정 파일이 없어서 저장할 수 없어요.');
      return;
    }
    setState(() => _error = null);
    try {
      final issues = RegistryHolder.of(context).read<ConfigValidator>().validate(config);
      if (issues.isNotEmpty) {
        if (!mounted) return;
        setState(() => _error = '설정 파일에 고칠 곳이 ${issues.length}군데 있어요.');
        return;
      }
      await RegistryHolder.of(context).read<ProjectRepository>().updateProject(project);
      if (!mounted) return;
      setState(() => _loading = false);
    } on PpolingException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return AppPage(
        crumbs: const [('개발', '/home'), ('설정', null)],
        children: [
          const PageHead(title: '프로젝트 설정', sub: '설정을 불러오는 중이에요.'),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if (_error != null) {
      return AppPage(
        crumbs: const [('개발', '/home'), ('설정', null)],
        children: [
          const PageHead(title: '프로젝트 설정', sub: '설정을 불러오지 못했어요.'),
          Notice(
            bg: C.bad.$1,
            border: const Color(0xFFF3B8B2),
            icon: Icons.error_outline,
            iconColor: const Color(0xFF7A1C14),
            child: Text(_error!, style: const TextStyle(fontSize: 14, color: Color(0xFF7A1C14))),
          ),
        ],
      );
    }

    final project = _project!;
    final config = project.config;
    final issues = project.configIssues;

    return AppPage(
      crumbs: [('개발', '/home'), (project.name, '/dashboard'), ('설정', null)],
      children: [
        PageHead(
          title: '프로젝트 설정',
          sub: '${project.folderPath}${Platform.pathSeparator}popoling.yaml',
          subMono: true,
          actions: [Btn('popoling.yaml 열기'), Btn('저장', primary: true, onPressed: _save)],
        ),
        if (issues.isNotEmpty)
          Notice(
            bg: C.bad.$1,
            border: const Color(0xFFF3B8B2),
            icon: Icons.error_outline,
            iconColor: const Color(0xFF7A1C14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
              const Text('저장할 수 없어요 — 설정 파일에 고칠 곳이 있어요.', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF7A1C14))),
              for (final issue in issues)
                Text(
                  issue.toString(),
                  style: const TextStyle(fontSize: 13, color: Color(0xFF7A1C14)),
                ),
            ]),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
          Expanded(
            child: Panel(
              title: '프로젝트 소개',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
                field('이름', project.name, onChanged: (v) => setState(() => _project = project.copyWith(name: v.trim()))),
                field('한 줄 설명', config?.about.summary ?? '', onChanged: (v) => setState(() => _project = project.copyWith(config: project.config!.copyWith(about: project.config!.about.copyWith(summary: v.isEmpty ? null : v))))),
                field('기술 스택 (쉼표로 구분)', config?.about.stack.join(', ') ?? '', hint: '예: Spring Boot, React, MySQL', onChanged: (v) => setState(() => _project = project.copyWith(config: project.config!.copyWith(about: project.config!.about.copyWith(stack: v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()))))),
                field('저장소 링크', config?.about.links['repo'] ?? '', isMono: true, onChanged: (v) => setState(() => _project = project.copyWith(config: project.config!.copyWith(about: project.config!.about.copyWith(links: {...project.config!.about.links, if (v.isNotEmpty) 'repo': v}))))),
                field('메모', config?.about.memo ?? '', lines: 3, onChanged: (v) => setState(() => _project = project.copyWith(config: project.config!.copyWith(about: project.config!.about.copyWith(memo: v.isEmpty ? null : v))))),
                const Text('처음 등록할 때 README 첫 문단과 Git 원격 주소로 채워졌어요.', style: TextStyle(fontSize: 12, color: C.muted)),
              ]),
            ),
          ),
          Expanded(flex: 2, child: _services(config?.services ?? const [])),
        ]),
      ],
    );
  }

  Widget _services(List<ServiceConfig> serviceList) {
    Widget kind(ServiceConfig s) {
      if (s is ProcessService) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
          const Tag('프로세스'),
          Text('명령: ${s.command.join(' ')}  (폴더: ${s.cwd})', style: const TextStyle(fontSize: 12, color: C.muted)),
          if (s.ports.isNotEmpty) Text('포트: ${s.ports.join(', ')}', style: const TextStyle(fontSize: 12, color: C.muted)),
        ]);
      }
      if (s is ComposeService) {
        final svcs = s.services;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
          const Tag('Docker Compose'),
          Text('파일: ${s.file}  (서비스: ${svcs.isEmpty ? '전체' : svcs.join(', ')})', style: const TextStyle(fontSize: 12, color: C.muted)),
        ]);
      }
      if (s is RemoteService) {
        return const Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
          Tag('원격 연결'),
          Text('켜고 끄지 않고 연결만 확인', style: TextStyle(fontSize: 12, color: C.muted)),
        ]);
      }
      return const SizedBox.shrink();
    }

    return Panel(
      title: '실행 항목',
      titleAction: const Btn('항목 추가'),
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final s in serviceList)
          Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
            Row(spacing: 10, children: [
              Expanded(child: Text(s.id, style: const TextStyle(fontWeight: FontWeight.w700))),
              kind(s),
              if (s.dependsOn.isNotEmpty)
                Text('의존: ${s.dependsOn.join(', ')}', style: const TextStyle(fontSize: 12, color: C.muted)),
            ]),
            if (s != serviceList.last) Container(height: 1, color: C.divider),
          ]),
      ]),
    );
  }
}
