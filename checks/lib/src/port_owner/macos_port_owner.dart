import 'package:ppoling_core/models.dart';

import 'port_owner_lookup.dart';

/// macOS: `lsof` 로 포트를 LISTEN 하는 PID·프로그램 이름을 찾는다.
///
/// `lsof` 는 관리자 권한 없이는 내 계정의 프로세스만 보여주므로, 못 찾아도 [PortFree] 라고 하지 않고 null 을 돌려준다.
/// 아이콘으로 켠 앱은 PATH 가 짧아서 전체 경로로 부른다.
class MacosPortOwner implements PortOwnerLookup {
  // ignore: prefer_initializing_formals, 이름 있는 매개변수는 _ 로 시작할 수 없다
  MacosPortOwner({RunProcess run = runProcess}) : _run = run;

  static const lsof = '/usr/sbin/lsof';

  final RunProcess _run;

  @override
  Future<PortUsage?> find(int port) async {
    try {
      // -n·-P: 주소·포트 이름을 찾지 않아 빠르다. -F pc: PID·이름만 기계가 읽기 좋게.
      final result = await _run(lsof, ['-nP', '-iTCP:$port', '-sTCP:LISTEN', '-F', 'pc']);
      return lsofOwner('${result.stdout}', port); // 못 찾으면 종료 코드 1, 출력 없음
    } on Exception {
      return null;
    }
  }
}

/// `lsof -F pc` 출력(`p1234`, `cnode` 줄)의 첫 프로세스. 없으면 null.
PortInUse? lsofOwner(String lsof, int port) {
  int? pid;
  String? name;
  for (final line in lsof.split('\n').map((l) => l.trim())) {
    if (line.startsWith('p')) {
      if (pid != null) break; // 첫 프로세스만
      pid = int.tryParse(line.substring(1));
    } else if (line.startsWith('c') && pid != null) {
      name = line.substring(1);
    }
  }
  return pid == null ? null : PortInUse(port, pid: pid, processName: name);
}
