import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// macOS: 중계를 새 프로세스 그룹의 리더로 만든다. 서비스와 그 자식도 이 그룹에 들어, 앱이 그룹째 멈출 수 있다.
void becomeGroupLeader() {
  final setpgid = DynamicLibrary.process().lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>('setpgid');
  setpgid(0, 0);
}

/// Windows: 앱이 만든 이름 붙은 Job 의 핸들을 열어 중계가 끝날 때까지 쥔다.
/// 이름 붙은 객체는 핸들이 모두 닫히면 이름으로 찾을 수 없게 되니, 앱이 꺼진 뒤를 위해 중계가 쥐고 있는다.
void holdJob(String name) {
  const jobObjectQuery = 0x0004;
  final openJobObject = DynamicLibrary.open('kernel32.dll').lookupFunction<
      Pointer<Void> Function(Uint32, Int32, Pointer<Utf16>), Pointer<Void> Function(int, int, Pointer<Utf16>)>('OpenJobObjectW');
  using((arena) => openJobObject(jobObjectQuery, 0, name.toNativeUtf16(allocator: arena))); // 핸들은 프로세스가 끝날 때 닫힌다
}
