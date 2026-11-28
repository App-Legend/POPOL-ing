import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

import 'api_key_dialog.dart';
import 'api_key_status.dart';
import 'api_key_store.dart';

/// 앱 설정(왼쪽 메뉴 [앱 설정], `/app-settings`, #105). 지금은 Gemini API 키 한 가지만 둔다.
///
/// 키 말고 다른 항목은 팀에 제안하고 기획서에 적은 뒤에 넣는다.
class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key, required this.keys, required this.client, this.checkKey});

  final ApiKeyStore keys;

  /// 모델 이름(`modelName`)을 보여 준다.
  final LlmClient client;

  /// 키 입력 창의 [연결 확인]. null 이면 버튼이 없다.
  final ApiKeyCheck? checkKey;

  @override
  Widget build(BuildContext context) {
    const note = TextStyle(fontSize: 13, color: C.text2, height: 1.6);
    return AppPage(
      crumbs: const [('앱 설정', null)],
      children: [
        const Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
          Text('앱 설정', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          Text('이 컴퓨터의 포폴링에만 적용돼요. 팀원과 나누지 않아요.', style: TextStyle(fontSize: 14, color: C.text2)),
        ]),
        Panel(
          title: 'Gemini API 키',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
            ApiKeyStatus(keys: keys, client: client, checkKey: checkKey),
            const Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
              Icon(Icons.lock_outline, size: 16, color: C.muted),
              Expanded(
                child: Text('키는 이 컴퓨터의 보안 저장소에만 두고, 화면에는 끝 4자리만 보여요. popoling.yaml과 로그에는 쓰지 않아요.', style: note),
              ),
            ]),
            const Text('키가 없어도 실행·종료·헬스체크는 그대로 쓸 수 있어요. AI 분석([원인 분석]·[AI 요약])에만 필요해요.', style: note),
          ]),
        ),
      ],
    );
  }
}
