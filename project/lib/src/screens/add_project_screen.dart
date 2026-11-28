import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

import '../command_summary.dart';
import '../file_project_repository.dart';

/// 프로젝트 추가(FR-01). 개발 홈의 [프로젝트 추가]·[프로젝트 폴더 고르기]가 `/add-project` 로 연다.
///
/// 폴더의 popoling.yaml 에 실행할 명령이 있으면 등록하기 전에 그 목록을 보여 주고 확인받는다.
/// 남이 만든 설정의 명령이 확인 없이 실행되지 않게 하려고. 등록되면 그 프로젝트 화면으로 간다.
class AddProjectScreen extends StatefulWidget {
  const AddProjectScreen({
    super.key,
    required this.projects,
    this.pickFolder = _pick,
    this.readConfig = FileProjectRepository.withFolderConfig,
  });

  final ProjectRepository projects;

  /// 폴더 고르기 창. 닫으면 null.
  final Future<String?> Function() pickFolder;

  /// 등록 전에 폴더의 popoling.yaml 을 읽어 붙인다. 등록할 때 저장소가 읽는 것과 같은 방법이다.
  final Future<Project> Function(Project) readConfig;

  static Future<String?> _pick() => getDirectoryPath(confirmButtonText: '이 폴더 고르기');

  @override
  State<AddProjectScreen> createState() => _AddProjectScreenState();
}

class _AddProjectScreenState extends State<AddProjectScreen> {
  final _name = TextEditingController();
  String? _folder;
  String? _error;

  /// 이미 등록된 폴더면 그 프로젝트 ID. [그 프로젝트로 이동]에 쓴다.
  String? _existingId;
  var _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    final folder = await widget.pickFolder();
    if (folder == null || !mounted) return;
    setState(() {
      _folder = folder;
      _name.text = folder.split(RegExp(r'[/\\]')).lastWhere((s) => s.isNotEmpty, orElse: () => folder);
      _error = null;
      _existingId = null;
    });
  }

  Future<void> _register() async {
    final folder = _folder!;
    setState(() {
      _busy = true;
      _error = null;
      _existingId = null;
    });
    try {
      final preview = await widget.readConfig(Project(id: 'preview', name: _name.text, folderPath: folder, registeredAt: DateTime.now()));
      final services = preview.config?.services ?? const <ServiceConfig>[];
      // 형식 문제가 있으면 실행이 막히니 확인할 명령이 없다
      if (services.isNotEmpty && preview.configIssues.isEmpty && !await _confirm(services)) return;
      final project = await widget.projects.addProject(folder, name: _name.text);
      if (mounted) await Navigator.pushReplacementNamed(context, '/dashboard', arguments: project.id);
    } on ProjectAlreadyRegisteredException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _existingId = e.projectId;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e is PopolingException ? e.message : '등록하지 못했어요: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(List<ServiceConfig> services) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => Dialog(
          child: DialogBody('이 폴더의 명령을 확인해 주세요', maxWidth: 560, [
            const Text('[전체 실행]을 누르면 아래 명령이 실행돼요. 직접 만든 설정이 아니면 내용을 꼭 확인해 주세요.',
                style: TextStyle(fontSize: 14, color: C.text2, height: 1.6)),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.headBg, border: Border.all(color: C.border), borderRadius: BorderRadius.circular(8)),
              child: SelectableText(summarizeCommands(services), style: mono.copyWith(fontSize: 12.5, color: C.text, height: 1.6)),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: [
              OutlinedButton(autofocus: true, onPressed: () => closeDialog(c, false), child: const Text('취소')),
              FilledButton(onPressed: () => closeDialog(c, true), child: const Text('확인하고 등록')),
            ]),
          ]),
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600);
    return AppPage(crumbs: const [('내 프로젝트', '/home'), ('프로젝트 추가', null)], children: [
      const PageHead(title: '프로젝트 추가', sub: '프로젝트 폴더를 고르면 실행 방법(popoling.yaml)을 찾아 불러와요.'),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
          const Text('폴더', style: label),
          Row(spacing: 12, children: [
            Expanded(
              child: Text(_folder ?? '아직 고르지 않았어요',
                  style: _folder == null ? const TextStyle(fontSize: 14, color: C.muted) : mono.copyWith(fontSize: 13.5, color: C.text)),
            ),
            Btn('폴더 고르기', icon: Icons.folder_open, onPressed: _busy ? null : _choose),
          ]),
          const Text('이름', style: label),
          TextField(
            key: const ValueKey('add-project-name'),
            controller: _name,
            enabled: _folder != null && !_busy,
            decoration: const InputDecoration(hintText: '비워 두면 폴더 이름을 써요', isDense: true, border: OutlineInputBorder()),
          ),
          if (_error case final error?)
            Notice(
              bg: C.bad.$1,
              border: C.bad.$2.withValues(alpha: 0.3),
              icon: Icons.error_outline,
              iconColor: C.bad.$2,
              trailing: [
                if (_existingId case final id?)
                  Btn('그 프로젝트로 이동', small: true, onPressed: () => Navigator.pushReplacementNamed(context, '/dashboard', arguments: id)),
              ],
              child: Text(error, style: TextStyle(fontSize: 14, color: C.bad.$2)),
            ),
          const Text('실행할 명령이 있으면 등록하기 전에 목록을 보여 주고 확인받아요. 폴더 안의 파일은 바꾸거나 지우지 않아요.', style: TextStyle(fontSize: 13, color: C.muted)),
          Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: [
            Btn('취소', onPressed: () => Navigator.maybePop(context)),
            Btn('등록하기', primary: true, onPressed: _folder == null || _busy ? null : _register),
          ]),
        ]),
      ),
    ]);
  }
}
