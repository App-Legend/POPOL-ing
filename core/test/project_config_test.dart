import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_core/models.dart';

/// 기획서 §7 스키마 예시를 YAML 라이브러리가 읽었을 때와 같은 모양의 Map.
Map<String, Object?> planExample() => {
      'version': 1,
      'name': 'my-team-project',
      'about': {
        'summary': '동아리 행사 예약 웹서비스 (2025 캡스톤)',
        'stack': ['Spring Boot', 'React', 'MySQL'],
        'links': {'repo': 'https://github.com/example/my-team-project'},
        'memo': '관리자 계정은 .env 의 ADMIN_* 참고',
      },
      'requires': [
        {'cli': 'node', 'version': '>=20'},
        {'cli': 'java', 'version': '>=17'},
        {'docker': true},
      ],
      'services': [
        {
          'id': 'db',
          'type': 'compose',
          'file': './docker-compose.yml',
          'services': ['mysql'],
          'ready': {'type': 'compose-healthy', 'timeout': 90},
        },
        {
          'id': 'api',
          'type': 'process',
          'cwd': './backend',
          'command': ['./gradlew', 'bootRun'],
          'env': {'SPRING_PROFILES_ACTIVE': 'local'},
          'envFile': './backend/.env',
          'ports': [8080],
          'dependsOn': ['db'],
          'ready': {'type': 'http', 'url': 'http://localhost:8080/actuator/health', 'timeout': 120},
          'stopTimeout': 15,
        },
        {
          'id': 'web',
          'type': 'process',
          'cwd': './frontend',
          'command': ['npm', 'run', 'dev'],
          'ports': [5173],
          'dependsOn': ['api'],
          'ready': {'type': 'port', 'port': 5173},
        },
        {
          'id': 'storage',
          'type': 'remote',
          'ready': {'type': 'http', 'url': 'https://storage.my-team.dev/health', 'timeout': 10},
        },
      ],
      'checks': [
        {'name': '프론트 메인', 'url': 'http://localhost:5173'},
        {'name': 'API 헬스', 'url': 'http://localhost:8080/actuator/health', 'expectStatus': 200},
      ],
    };

/// [map] 을 읽었을 때 나온 문제들의 위치.
List<String> issuePaths(Map<String, Object?> map) {
  try {
    ProjectConfig.fromMap(map);
    return const [];
  } on ConfigFormatException catch (e) {
    return [for (final issue in e.issues) issue.path];
  }
}

/// 실행 항목 하나만 있는 최소 설정.
Map<String, Object?> withService(Map<String, Object?> service) => {
      'version': 1,
      'services': [service],
    };

void main() {
  group('기획서 §7 예시', () {
    late ProjectConfig config;
    setUp(() => config = ProjectConfig.fromMap(planExample()));

    test('소개와 환경 점검 대상을 읽는다', () {
      expect(config.version, 1);
      expect(config.about.summary, '동아리 행사 예약 웹서비스 (2025 캡스톤)');
      expect(config.about.stack, ['Spring Boot', 'React', 'MySQL']);
      expect(config.about.links['repo'], 'https://github.com/example/my-team-project');
      expect(config.requires, hasLength(3));
      expect(config.requires.last, isA<DockerRequirement>());
      expect((config.requires.first as CliRequirement).version, '>=20');
    });

    test('실행 항목 4개를 종류에 맞게 읽는다', () {
      final [db, api, web, storage] = config.services;
      expect(db, isA<ComposeService>().having((s) => s.services, 'services', ['mysql']));
      expect(db.ready, isA<ComposeHealthyReady>().having((r) => r.timeout, 'timeout', const Duration(seconds: 90)));

      api as ProcessService;
      expect(api.command, ['./gradlew', 'bootRun']);
      expect(api.cwd, './backend');
      expect(api.env, {'SPRING_PROFILES_ACTIVE': 'local'});
      expect(api.ports, [8080]);
      expect(api.dependsOn, ['db']);
      expect(api.stopTimeout, const Duration(seconds: 15));
      expect(api.ready, isA<HttpReady>().having((r) => r.url, 'url', 'http://localhost:8080/actuator/health'));

      expect(web.ready, isA<PortReady>().having((r) => r.port, 'port', 5173));
      expect(web.ready.timeout, ReadyCondition.defaultTimeout);
      expect(storage, isA<RemoteService>());
    });

    test('QA 검사를 읽는다', () {
      expect([for (final c in config.checks) c.name], ['프론트 메인', 'API 헬스']);
      expect(config.checks.last.expectStatus, 200);
    });
  });

  group('기본값', () {
    test('version 만 있어도 된다', () {
      final config = ProjectConfig.fromMap({'version': 1});
      expect(config.services, isEmpty);
      expect(config.checks, isEmpty);
      expect(config.about.stack, isEmpty);
    });

    test('process 의 cwd·ready·stopTimeout 기본값', () {
      final config = ProjectConfig.fromMap(withService({'id': 'app', 'type': 'process', 'command': ['node', 'index.js']}));
      final app = config.services.single as ProcessService;
      expect(app.cwd, '.');
      expect(app.ready, isA<NoneReady>());
      expect(app.stopTimeout, ProcessService.defaultStopTimeout);
    });

    test('주소가 없는 check 도 형식 오류가 아니다(QA 에서 설정 필요로 보인다)', () {
      final config = ProjectConfig.fromMap({
        'version': 1,
        'checks': [
          {'name': '관리자 페이지'},
        ],
      });
      expect(config.checks.single.hasTarget, isFalse);
    });

    test('YAML 이 숫자로 읽은 환경변수 값은 글자로 받는다', () {
      final config = ProjectConfig.fromMap(withService({
        'id': 'app',
        'type': 'process',
        'command': ['node', 'index.js'],
        'env': {'PORT': 8080, 'DEBUG': true},
      }));
      expect((config.services.single as ProcessService).env, {'PORT': '8080', 'DEBUG': 'true'});
    });
  });

  group('형식 오류는 위치와 함께 알린다', () {
    test('version 이 없거나 1 이 아니면', () {
      expect(issuePaths({}), ['version']);
      expect(issuePaths({'version': 2}), ['version']);
    });

    test('이름 오타는 알 수 없는 항목으로', () {
      expect(
        issuePaths(withService({'id': 'web', 'type': 'process', 'command': ['npm'], 'dependOn': ['api']})),
        ['services[0].dependOn'],
      );
    });

    test('process 에 command 가 없거나, 목록이 아니거나, 비어 있으면', () {
      expect(issuePaths(withService({'id': 'a', 'type': 'process'})), ['services[0].command']);
      expect(issuePaths(withService({'id': 'a', 'type': 'process', 'command': 'npm run dev'})), ['services[0].command']);
      expect(issuePaths(withService({'id': 'a', 'type': 'process', 'command': []})), ['services[0].command']);
    });

    test('모르는 type, 빠진 id, 잘못된 id 글자', () {
      expect(issuePaths(withService({'id': 'a', 'type': 'docker'})), ['services[0].type']);
      expect(issuePaths(withService({'type': 'process', 'command': ['npm']})), ['services[0].id']);
      expect(issuePaths(withService({'id': 'my api', 'type': 'process', 'command': ['npm']})), ['services[0].id']);
    });

    test('프로젝트 폴더 밖을 가리키는 경로', () {
      expect(issuePaths(withService({'id': 'a', 'type': 'process', 'command': ['npm'], 'cwd': '../other'})), ['services[0].cwd']);
      expect(issuePaths(withService({'id': 'a', 'type': 'process', 'command': ['npm'], 'cwd': r'C:\Users'})), ['services[0].cwd']);
      expect(issuePaths(withService({'id': 'db', 'type': 'compose', 'file': '/etc/compose.yml'})), ['services[0].file']);
    });

    test('범위를 벗어난 포트는 그 칸을 알린다', () {
      expect(
        issuePaths(withService({'id': 'a', 'type': 'process', 'command': ['npm'], 'ports': [8080, 70000]})),
        ['services[0].ports[1]'],
      );
    });

    test('원격 항목은 ready 가 꼭 있어야 하고, port 면 host 도 있어야 한다', () {
      expect(issuePaths(withService({'id': 'r', 'type': 'remote'})), ['services[0].ready']);
      expect(
        issuePaths(withService({'id': 'r', 'type': 'remote', 'ready': {'type': 'port', 'port': 5432}})),
        ['services[0].ready.host'],
      );
      expect(
        issuePaths(withService({'id': 'r', 'type': 'remote', 'ready': {'type': 'log', 'pattern': 'ok'}})),
        ['services[0].ready.type'],
      );
    });

    test('잘못된 정규식과 주소', () {
      expect(
        issuePaths(withService({'id': 'a', 'type': 'process', 'command': ['npm'], 'ready': {'type': 'log', 'pattern': '('}})),
        ['services[0].ready.pattern'],
      );
      expect(
        issuePaths(withService({'id': 'a', 'type': 'process', 'command': ['npm'], 'ready': {'type': 'http', 'url': 'localhost:8080'}})),
        ['services[0].ready.url'],
      );
    });

    test('check 에 url 과 port 를 같이 쓰면', () {
      expect(
        issuePaths({
          'version': 1,
          'checks': [
            {'name': 'x', 'url': 'http://localhost', 'port': 80},
          ],
        }),
        ['checks[0]'],
      );
    });

    test('문제가 여러 곳이면 첫 문제에서 멈추지 않고 모두 알린다', () {
      final paths = issuePaths({
        'version': 1,
        'services': [
          {'id': 'a', 'type': 'process'},
          {'id': 'b', 'type': 'compose'},
        ],
        'checks': [
          {'url': 'http://localhost'},
        ],
      });
      expect(paths, ['services[0].command', 'services[1].file', 'checks[0].name']);
    });

    test('ConfigFormatException 의 문장은 화면에 보여줄 수 있다', () {
      expect(
        () => ProjectConfig.fromMap({'version': 1, 'services': 'db'}),
        throwsA(isA<ConfigFormatException>()
            .having((e) => e.message, 'message', 'ppoling.yaml 에서 고칠 곳이 1군데 있어요.')
            .having((e) => e.issues.single.path, 'path', 'services')),
      );
    });
  });

  group('toMap 왕복', () {
    /// fromMap → toMap → fromMap → toMap 이 같고, 첫 toMap 이 [normalized] 와 같은지 본다.
    void expectRoundTrip(Map<String, Object?> source, Map<String, Object?> normalized) {
      final first = ProjectConfig.fromMap(source).toMap();
      expect(first, equals(normalized));
      final second = ProjectConfig.fromMap(first).toMap();
      expect(second, equals(first));
    }

    test('기획서 §7 예시는 그대로 돌아온다', () {
      expectRoundTrip(planExample(), planExample());
    });

    test('모든 종류를 쓴 설정은 그대로 돌아온다', () {
      final all = <String, Object?>{
        'version': 1,
        'name': 'all-kinds',
        'about': {
          'summary': '모든 종류',
          'stack': ['Dart'],
          'links': {'repo': 'https://example.com/r'},
          'memo': '메모',
        },
        'requires': [
          {'cli': 'node', 'version': '>=20'},
          {'cli': 'git'},
          {'docker': true},
        ],
        'services': [
          {
            'id': 'p1',
            'type': 'process',
            'cwd': './a',
            'command': ['npm', 'run', 'dev'],
            'env': {'PORT': '8080'},
            'envFile': './a/.env',
            'ports': [8080, 8081],
            'stopTimeout': 2.5,
            'dependsOn': ['c1'],
            'ready': {'type': 'log', 'pattern': 'Started .* in', 'timeout': 30, 'interval': 0.5},
          },
          {
            'id': 'p2',
            'type': 'process',
            'command': ['echo'],
            'ready': {'type': 'port', 'port': 3000, 'host': '127.0.0.1'},
          },
          {
            'id': 'p3',
            'type': 'process',
            'command': ['echo'],
            'ready': {'type': 'none', 'timeout': 5},
          },
          {
            'id': 'c1',
            'type': 'compose',
            'file': './docker-compose.yml',
            'ready': {'type': 'http', 'url': 'http://localhost:9000/h', 'expectStatus': 204},
          },
          {
            'id': 'c2',
            'type': 'compose',
            'file': './c2.yml',
            'services': ['db', 'cache'],
            'ready': {'type': 'compose-healthy', 'interval': 2},
          },
          {
            'id': 'r1',
            'type': 'remote',
            'ready': {'type': 'http', 'url': 'https://r.example.com/health'},
          },
          {
            'id': 'r2',
            'type': 'remote',
            'ready': {'type': 'port', 'port': 5432, 'host': 'db.example.com'},
            'dependsOn': ['r1'],
          },
        ],
        'checks': [
          {'name': 'URL', 'url': 'http://localhost:1/', 'expectStatus': 200},
          {'name': 'PORT', 'port': 3306, 'host': 'db.local'},
          {'name': '주소 없음'},
        ],
      };
      expectRoundTrip(all, all);
    });

    test('기본값을 적어도 toMap 에서는 빠진다', () {
      final explicit = <String, Object?>{
        'version': 1,
        'about': <String, Object?>{'stack': <Object?>[], 'links': <String, Object?>{}},
        'requires': <Object?>[],
        'services': [
          {
            'id': 'a',
            'type': 'process',
            'cwd': '.',
            'command': ['x'],
            'env': <String, Object?>{},
            'ports': <Object?>[],
            'stopTimeout': 10,
            'dependsOn': <Object?>[],
            'ready': {'type': 'none', 'timeout': 60, 'interval': 1},
          },
          {
            'id': 'b',
            'type': 'process',
            'command': ['y'],
            'ready': {'type': 'port', 'port': 1, 'timeout': 60.0, 'interval': 1.0},
          },
        ],
      };
      final expected = <String, Object?>{
        'version': 1,
        'services': [
          {'id': 'a', 'type': 'process', 'command': ['x']},
          {
            'id': 'b',
            'type': 'process',
            'command': ['y'],
            'ready': {'type': 'port', 'port': 1},
          },
        ],
      };
      expectRoundTrip(explicit, expected);
    });

    test('시간은 딱 떨어지면 정수, 아니면 소수로 쓴다', () {
      const service = ProcessService(
        id: 'a',
        command: ['x'],
        stopTimeout: Duration(milliseconds: 1500),
        ready: LogReady(pattern: 'ok', timeout: Duration(seconds: 90)),
      );
      final map = service.toMap();
      expect(map['stopTimeout'], isA<double>().having((v) => v, 'value', 1.5));
      expect((map['ready']! as Map)['timeout'], isA<int>().having((v) => v, 'value', 90));
    });

    test('반환한 Map 을 고쳐도 원본 설정은 그대로다', () {
      final config = ProjectConfig.fromMap(planExample());
      final map = config.toMap();
      ((map['services']! as List).first as Map)['id'] = 'changed';
      ((map['about']! as Map)['stack']! as List).add('X');
      expect(config.services.first.id, 'db');
      expect(config.about.stack, ['Spring Boot', 'React', 'MySQL']);
    });
  });
}
