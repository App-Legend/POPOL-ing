import 'package:popoling_core/models.dart';

import 'port_owner_lookup.dart';

/// Windows: `netstat -ano` 로 PID 를, `tasklist` 로 프로그램 이름을 찾는다.
///
/// `netstat -ano` 는 관리자 권한 없이도 모든 프로세스의 PID 를 보여주므로, 못 찾으면 [PortFree] 다.
class WindowsPortOwner implements PortOwnerLookup {
  // ignore: prefer_initializing_formals, 이름 있는 매개변수는 _ 로 시작할 수 없다
  WindowsPortOwner({RunProcess run = runProcess}) : _run = run;

  final RunProcess _run;

  @override
  Future<PortUsage?> find(int port) async {
    final String netstat;
    try {
      final result = await _run('netstat', ['-ano', '-p', 'TCP']);
      final v6 = await _run('netstat', ['-ano', '-p', 'TCPv6']);
      if (result.exitCode != 0) return null;
      netstat = '${result.stdout}\n${v6.exitCode == 0 ? v6.stdout : ''}';
    } on Exception {
      return null;
    }
    final pid = listeningPid(netstat, port);
    if (pid == null) return PortFree(port);
    return PortInUse(port, pid: pid, processName: await _name(pid));
  }

  Future<String?> _name(int pid) async {
    try {
      final result = await _run('tasklist', ['/FI', 'PID eq $pid', '/FO', 'CSV', '/NH']);
      return result.exitCode == 0 ? tasklistName('${result.stdout}') : null;
    } on Exception {
      return null;
    }
  }
}

/// `netstat -ano` 출력에서 [port] 를 LISTEN 하는 PID. 상태 이름(`LISTENING`)은 OS 언어마다 달라서
/// 상대 주소 포트가 0 인 줄(`0.0.0.0:0`, `[::]:0`)을 LISTEN 으로 본다.
int? listeningPid(String netstat, int port) {
  for (final line in netstat.split('\n')) {
    final cols = line.trim().split(RegExp(r'\s+'));
    if (cols.length < 5 || cols.first != 'TCP') continue;
    if (_portOf(cols[1]) != port || _portOf(cols[2]) != 0) continue;
    final pid = int.tryParse(cols.last);
    if (pid != null && pid > 0) return pid;
  }
  return null;
}

int? _portOf(String address) => int.tryParse(address.substring(address.lastIndexOf(':') + 1));

/// `tasklist /FO CSV /NH` 출력(`"node.exe","1234",...`)의 첫 칸. 못 찾으면 안내 문장만 나오므로 null.
String? tasklistName(String tasklist) {
  for (final line in tasklist.split('\n')) {
    final match = RegExp(r'^"([^"]+)"').firstMatch(line.trim());
    if (match != null) return match.group(1);
  }
  return null;
}
