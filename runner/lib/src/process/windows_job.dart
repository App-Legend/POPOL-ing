import 'dart:ffi';
import 'dart:io' show pid;

import 'package:ffi/ffi.dart';

/// Windows Job Object 하나. 프로세스를 넣으면 그 뒤에 생기는 자식·손자도 같은 Job 에 들어가,
/// 부모가 먼저 끝나도 Job 째 멈출 수 있다(macOS 의 프로세스 그룹 역할).
///
/// 핸들로만 다루므로 PID 가 재사용돼도 남의 프로세스를 멈추지 않는다. 다 쓰면 [close] 한다.
class WindowsJob {
  WindowsJob() : _job = _createJobObject(nullptr, nullptr) {
    if (_job == nullptr) throw StateError('Windows Job Object 를 만들 수 없어요.');
  }

  final Pointer<Void> _job;
  var _closed = false;

  /// 이 앱이 띄운 [childPid] 프로세스를 이 Job 에 넣는다. 이미 끝났거나, 열 수 없거나,
  /// 그 PID 가 벌써 남의 프로세스에 재사용됐으면(부모가 이 앱이 아니면) 넣지 않고 false.
  bool assign(int childPid) {
    final process = _openProcess(_processSetQuota | _processTerminate | _processQueryLimitedInformation, 0, childPid);
    if (process == nullptr) return false;
    try {
      // 핸들을 연 동안은 PID 가 재사용되지 않으니, 연 뒤에 부모를 확인하면 충분하다.
      return _parentPid(process) == pid && _assignProcessToJobObject(_job, process) != 0;
    } finally {
      _closeHandle(process);
    }
  }

  /// Job 안의 프로세스를 모두 강제 종료한다. 실패하면 false.
  bool terminate() => !_closed && _terminateJobObject(_job, 1) != 0;

  /// Job 안에 살아 있는 프로세스 수. 닫았으면 0, 물어보지 못했으면 null.
  int? get activeProcesses {
    if (_closed) return 0;
    final info = calloc<Uint8>(_accountingInfoSize);
    try {
      if (_queryInformationJobObject(_job, _jobObjectBasicAccountingInformation, info.cast(), _accountingInfoSize, nullptr) == 0) {
        return null;
      }
      // JOBOBJECT_BASIC_ACCOUNTING_INFORMATION: LARGE_INTEGER 4개(32바이트) 뒤 DWORD
      // TotalPageFaultCount, TotalProcesses, ActiveProcesses, TotalTerminatedProcesses.
      return info.cast<Uint32>()[10];
    } finally {
      calloc.free(info);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _closeHandle(_job);
  }
}

/// [process] 의 부모 PID. 물어보지 못했으면 null.
int? _parentPid(Pointer<Void> process) {
  // PROCESS_BASIC_INFORMATION(64비트): ... UniqueProcessId(오프셋 32), InheritedFromUniqueProcessId(40). 48바이트.
  final info = calloc<Uint8>(48);
  try {
    if (_ntQueryInformationProcess(process, 0, info.cast(), 48, nullptr) != 0) return null;
    return info.cast<Uint64>()[5];
  } finally {
    calloc.free(info);
  }
}

const _processTerminate = 0x0001;
const _processSetQuota = 0x0100;
const _processQueryLimitedInformation = 0x1000;
const _jobObjectBasicAccountingInformation = 1;
const _accountingInfoSize = 48;

final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _createJobObject = _kernel32.lookupFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Utf16>),
    Pointer<Void> Function(Pointer<Void>, Pointer<Utf16>)>('CreateJobObjectW');
final _openProcess = _kernel32
    .lookupFunction<Pointer<Void> Function(Uint32, Int32, Uint32), Pointer<Void> Function(int, int, int)>('OpenProcess');
final _assignProcessToJobObject = _kernel32.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Void>),
    int Function(Pointer<Void>, Pointer<Void>)>('AssignProcessToJobObject');
final _terminateJobObject = _kernel32
    .lookupFunction<Int32 Function(Pointer<Void>, Uint32), int Function(Pointer<Void>, int)>('TerminateJobObject');
final _queryInformationJobObject = _kernel32.lookupFunction<
    Int32 Function(Pointer<Void>, Int32, Pointer<Void>, Uint32, Pointer<Uint32>),
    int Function(Pointer<Void>, int, Pointer<Void>, int, Pointer<Uint32>)>('QueryInformationJobObject');
final _ntQueryInformationProcess = DynamicLibrary.open('ntdll.dll').lookupFunction<
    Int32 Function(Pointer<Void>, Int32, Pointer<Void>, Uint32, Pointer<Uint32>),
    int Function(Pointer<Void>, int, Pointer<Void>, int, Pointer<Uint32>)>('NtQueryInformationProcess');
final _closeHandle =
    _kernel32.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('CloseHandle');
