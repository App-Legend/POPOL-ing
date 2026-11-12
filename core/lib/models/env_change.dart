/// 마지막 성공 실행 때와 지금 환경이 달라진 것 하나(FR-16). 예: Node 20 → 22
class EnvChange {
  const EnvChange({required this.name, this.before, this.after});

  /// 바뀐 도구 이름. 예: `node`, `docker`
  final String name;

  /// 마지막 성공 때 버전. 그때는 없었으면 null.
  final String? before;

  /// 지금 버전. 지금은 없으면(미설치) null.
  final String? after;
}
