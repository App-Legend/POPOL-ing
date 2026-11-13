/// 초 단위로 쓴다. 딱 떨어지면 int, 아니면 double. 패키지 안에서만 쓴다.
num durationToSeconds(Duration d) => d.inMilliseconds % 1000 == 0 ? d.inSeconds : d.inMilliseconds / 1000;
