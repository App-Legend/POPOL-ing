/// 화면에 보여 줄 로그 한 줄. `stream` 은 `out`·`err`·`포폴링`.
typedef LogLine = ({String time, String stream, String text});

/// `LogStore` 한 줄(`<시각> out|err | <내용>` 또는 `--- 시작 <시각> ---`)을 나눈다.
LogLine parseLogLine(String l) {
  if (RegExp(r'^--- 시작 (\S+) ---$').firstMatch(l) case final m?) {
    return (time: clockOf(m[1]!), stream: '포폴링', text: '실행 시작');
  }
  if (RegExp(r'^(\S+) (out|err) \| (.*)$').firstMatch(l) case final m?) {
    return (time: clockOf(m[1]!), stream: m[2]!, text: m[3]!);
  }
  return (time: '', stream: 'out', text: l);
}

/// ISO 시각에서 `HH:mm:ss` 만.
String clockOf(String iso) => DateTime.tryParse(iso)?.toIso8601String().substring(11, 19) ?? iso;
