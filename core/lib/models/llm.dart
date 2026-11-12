/// AI 호출이 실패한 이유. 화면에서 이유마다 다른 다음 조치를 안내한다.
enum LlmFailure {
  /// API 키를 아직 넣지 않았다. [키 입력]을 보여준다.
  missingKey,

  /// API 키가 틀렸거나 막혔다.
  invalidKey,

  /// 사용량 제한을 넘었다. 잠시 뒤 다시 하라고 안내한다.
  quotaExceeded,

  /// 인터넷 연결이나 서버 응답 문제.
  network,
}
