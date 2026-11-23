import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

/// 상태 칩. 색만으로 구분하지 않게 라벨을 함께 쓴다(기획서 §6 라벨).
StatusChip stateChip(ItemState state) => switch (state) {
      ItemState.stopped => const StatusChip('중지', C.idle),
      ItemState.starting => const StatusChip('시작 중', C.warn),
      ItemState.running => const StatusChip('실행 중 · 준비 대기', C.warn),
      ItemState.ready => const StatusChip('준비 완료', C.ok),
      ItemState.stopping => const StatusChip('종료 중', C.warn),
      ItemState.failed => const StatusChip('실패', C.bad),
      ItemState.connected => const StatusChip('연결됨', C.ok),
      ItemState.disconnected => const StatusChip('연결 안 됨', C.bad),
      ItemState.portBusy => const StatusChip('포트 사용 중', C.port),
      ItemState.unknown => const StatusChip('확인 불가', C.idle),
    };

/// 떠 있거나 뜨는 중이라 [중지] 를 보여 줄 상태.
bool isUp(ItemState s) => s == ItemState.starting || s == ItemState.running || s == ItemState.ready;

/// 항목 유형 이름.
String kindOf(ServiceConfig s) => switch (s) {
      ProcessService() => '프로세스',
      ComposeService() => 'Compose',
      RemoteService() => '원격 연결',
    };

/// 준비 조건을 한 줄로.
String readyText(ReadyCondition r) => switch (r) {
      PortReady(:final host, :final port) => '포트 ${host ?? 'localhost'}:$port 열림',
      HttpReady(:final url, :final expectStatus) => 'HTTP $url${expectStatus == null ? '' : ' → $expectStatus'}',
      LogReady(:final pattern) => '로그에 "$pattern"',
      ComposeHealthyReady() => 'Compose healthcheck',
      NoneReady() => '없음(시작하면 준비 완료)',
    };

/// 결과 칩(성공·실패·건너뜀).
StatusChip outcomeChip(ItemOutcome o) => switch (o) {
      ItemOutcome.ok => const StatusChip('성공', C.ok, dot: false),
      ItemOutcome.failed => const StatusChip('실패', C.bad, dot: false),
      ItemOutcome.skipped => const StatusChip('건너뜀', C.idle, dot: false),
    };

/// 오케스트레이터 호출이 던진 예외를 화면 문장으로.
String errorText(Object e) => switch (e) {
      PopolingException(:final message) => message,
      ArgumentError(:final message) => '$message',
      _ => '처리하지 못했어요: $e',
    };

/// 화면 아래에 잠깐 알린다.
void toast(BuildContext context, String message) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
