import 'package:ppoling_core/models.dart';

/// AI 오류 안내 한 가지. 원인([title], [body])과 다음 조치([action] 버튼 이름)를 함께 보여준다.
class LlmErrorText {
  const LlmErrorText(this.title, this.body, this.action);

  final String title;
  final String body;
  final String action;
}

/// 실패 이유마다 다른 안내(기획서 §2 "키 오류·사용량 초과·네트워크 오류는 서로 구분해 안내한다",
/// 화면 문구 초안 §7).
LlmErrorText llmErrorText(LlmFailure failure) => switch (failure) {
      LlmFailure.missingKey => const LlmErrorText(
          'API 키 필요',
          'AI 분석을 하려면 Gemini API 키를 먼저 넣어 주세요. 다른 기능은 그대로 쓸 수 있어요.',
          '키 입력',
        ),
      LlmFailure.invalidKey => const LlmErrorText(
          'API 키가 맞지 않아요',
          '키가 틀렸거나 더 이상 쓸 수 없는 키예요. 키를 다시 확인하거나 Google AI Studio에서 새로 만들어 넣어 주세요.',
          '키 바꾸기',
        ),
      LlmFailure.quotaExceeded => const LlmErrorText(
          '사용량을 넘었어요',
          '지금 쓸 수 있는 AI 사용량을 넘었어요. 잠시 뒤에 다시 해 주세요. 무료 등급은 하루 사용량에도 제한이 있어요.',
          '다시 시도',
        ),
      LlmFailure.network => const LlmErrorText(
          '연결하지 못했어요',
          'AI 서버에 연결하지 못했거나 서버가 붐벼요. 인터넷 연결을 확인하고, 계속 안 되면 잠시 뒤에 다시 해 주세요. AI 말고 다른 기능은 그대로 쓸 수 있어요.',
          '다시 시도',
        ),
    };
