import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_core/models.dart';
import 'package:popoling_project/src/command_summary.dart';

void main() {
  group('summarizeCommands', () {
    test('서비스가 없으면 실행할 항목이 없다고 한다', () {
      expect(summarizeCommands(const []), '실행할 항목이 없어요.');
    });

    test('프로세스 서비스를 한 줄로 요약한다', () {
      final s = ProcessService(
        id: 'api',
        command: const ['./gradlew', 'bootRun'],
        cwd: './backend',
      );
      expect(
        summarizeCommands([s]),
        'api: gradlew bootRun (작업 폴더: ./backend)',
      );
    });

    test('docker compose 서비스를 요약한다', () {
      final s = ComposeService(id: 'db', file: './docker-compose.yml');
      expect(summarizeCommands([s]), 'db: Docker Compose 시작 (./docker-compose.yml)');
    });

    test('원격 서비스를 요약한다', () {
      final s = RemoteService(id: 'storage', ready: const NoneReady());
      expect(summarizeCommands([s]), 'storage: 원격 연결 확인');
    });
  });
}
