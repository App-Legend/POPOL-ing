import 'item_ref.dart';
import 'probe.dart';
import 'run.dart';

/// 항목이 실패한 원인(기획서 §8 실패 안내 카드). `ItemResult.cause`·`ItemStateChanged.cause`·`Orchestrator.causeOf` 로 받는다.
///
/// 종류마다 하위 클래스가 있다. 화면에서는 `switch` 로 나눠 §8 의 조치 버튼을 고른다
/// (예: [ReadyTimeout] 이면 [더 기다리기]·[준비 조건 바꾸기]·[끄기]). 그래서 추천 조치는 따로 담지 않는다.
/// 비밀값은 담지 않는다. `.env` 는 경로만, 로그 줄은 가린 뒤 담는다.
sealed class FailureCause {
  const FailureCause({this.evidence = const []});

  /// 근거가 된 로그 줄(오래된 줄이 앞). `.env` 값은 가린 뒤라 외부(Gemini API)로 보내도 된다. 없으면 빈 목록.
  final List<String> evidence;

  /// 이 원인일 때 항목의 상태.
  ItemState get state;
}

/// 시작 실패: 명령 오류. 명령을 띄우지 못했거나 준비되기 전에 스스로 끝났다.
final class CommandFailed extends FailureCause {
  const CommandFailed({this.exitCode, super.evidence});

  /// 끝났을 때의 종료 코드. 띄우지도 못했으면 null.
  final int? exitCode;

  @override
  ItemState get state => ItemState.startFailed;
}

/// 시작 실패: 명령을 찾을 수 없다(도구 없음).
final class ToolMissing extends FailureCause {
  const ToolMissing(this.tool, {super.evidence});

  /// 찾지 못한 명령 이름. 예: `java`, `npm`
  final String tool;

  @override
  ItemState get state => ItemState.startFailed;
}

/// 시작 실패: 항목의 `envFile` 이 없거나 읽을 수 없다.
final class EnvFileMissing extends FailureCause {
  const EnvFileMissing(this.path, {super.evidence});

  /// popoling.yaml 에 적힌 경로 그대로. 예: `api/.env`
  final String path;

  @override
  ItemState get state => ItemState.startFailed;
}

/// 포트 사용 중: 시작 전 포트 점검에서 걸려 시작하지 않았다.
final class PortBusy extends FailureCause {
  const PortBusy(this.usage, {this.owner, super.evidence});

  /// 누가 포트를 쓰는가. 포트 번호는 `usage.port`.
  final PortInUse usage;

  /// 포폴링이 띄운 내 항목이 쓰고 있으면 그 항목. 외부 프로그램이면 null(이름·PID 만 보여준다).
  final ItemRef? owner;

  @override
  ItemState get state => ItemState.portBusy;
}

/// 준비 시간 초과: 프로세스는 살아 있지만 [timeout] 안에 준비 조건을 채우지 못했다.
final class ReadyTimeout extends FailureCause {
  const ReadyTimeout(this.timeout, {super.evidence});

  final Duration timeout;

  @override
  ItemState get state => ItemState.readyTimeout;
}

/// 멈춤: `실행 중`·`준비 완료`·`준비 시간 초과` 였다가 0 이 아닌 종료 코드로 스스로 끝났다.
final class Crashed extends FailureCause {
  const Crashed({this.exitCode, super.evidence});

  /// 종료 코드. 앱을 다시 켠 뒤 끝나 알 수 없으면 null.
  final int? exitCode;

  @override
  ItemState get state => ItemState.crashed;
}
