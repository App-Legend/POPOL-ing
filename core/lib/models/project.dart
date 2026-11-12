import 'config_issue.dart';
import 'project_config.dart';

/// 프로젝트가 속한 카테고리. MVP 는 개발 하나뿐이다(기획서 §1).
enum ProjectCategory { dev }

/// 포폴링에 등록한 프로젝트 하나. 앱 데이터 영역의 프로젝트 목록에 저장된다.
class Project {
  const Project({
    required this.id,
    required this.name,
    required this.folderPath,
    required this.registeredAt,
    this.category = ProjectCategory.dev,
    this.config,
    this.configIssues = const [],
  });

  /// [id] 형식: 소문자·숫자·- 만. Compose 프로젝트 이름 `ppoling-<id>` 에 그대로 쓰기 때문이다.
  static final idPattern = RegExp(r'^[a-z0-9][a-z0-9-]*$');

  /// 등록할 때 정해지고 바뀌지 않는 ID. 다른 프로젝트와 겹치지 않는다.
  final String id;

  /// 화면에 보이는 이름.
  final String name;

  /// 프로젝트 폴더의 절대 경로.
  final String folderPath;

  /// 등록한 때.
  final DateTime registeredAt;

  final ProjectCategory category;

  /// 폴더의 ppoling.yaml 내용. 파일이 없거나 형식이 잘못돼 읽지 못했으면 null.
  final ProjectConfig? config;

  /// ppoling.yaml 을 읽다 찾은 문제. 문제가 없으면 빈 목록.
  final List<ConfigIssue> configIssues;

  /// 프로젝트 소개. 설정이 없으면 빈 소개.
  About get about => config?.about ?? const About();

  /// 이름이나 설정을 바꾼 사본. [id]·[folderPath]·[registeredAt] 은 바꿀 수 없다.
  Project copyWith({String? name, ProjectConfig? config, List<ConfigIssue>? configIssues}) => Project(
        id: id,
        name: name ?? this.name,
        folderPath: folderPath,
        registeredAt: registeredAt,
        category: category,
        config: config ?? this.config,
        configIssues: configIssues ?? this.configIssues,
      );
}
