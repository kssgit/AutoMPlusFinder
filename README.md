# AutoMPlusFinder

World of Warcraft Retail **한밤(Midnight) 시즌 2 / 12.1.0**용 Mythic+ 파티 찾기 보조 애드온입니다.

## 기능

- 현재 시즌 Mythic+ 던전을 게임 API에서 동적으로 읽어서 표시
- 원하는 던전 복수 선택
- 최소 / 최대 쐐기 단수 설정
- 신청 역할 선택: 탱커 / 힐러 / 공격 담당
- 파티 찾기 검색 결과에서 조건에 맞는 파티만 필터링
- 이미 신청한 파티 제외
- 5인으로 가득 찬 파티 제외
- 선택한 역할 자리가 남아 있지 않은 파티 제외
- 던전, 단수, 현재 인원, 역할 구성, 리더 쐐기 점수, 요구 점수, 공고 경과 시간 표시
- 새로운 조건 일치 파티가 검색 결과에 나타나면 소리 + 화면 메시지 알림
- 각 결과의 **신청** 버튼을 누르면 선택한 역할로 즉시 신청
- 설정과 창 위치 저장
- `/ampf` 명령으로 창 열기/닫기

## 중요한 WoW API 제한

Blizzard는 다음 함수에 **hardware event(키보드/마우스 입력)** 제한을 적용합니다.

- `C_LFGList.Search(...)`
- `C_LFGList.ApplyToGroup(...)`

따라서 애드온이 백그라운드에서 일정 주기로 자동 검색하거나, 조건에 맞는 파티가 발견되는 즉시 사용자 입력 없이 자동 신청하는 것은 불가능합니다.

AutoMPlusFinder는 이 제한을 지키기 위해:

1. 사용자가 `검색 / 갱신` 버튼을 클릭했을 때만 검색합니다.
2. 검색 결과는 자동으로 조건 필터링합니다.
3. 새 일치 파티가 있으면 알림을 냅니다.
4. 실제 신청은 해당 결과의 `신청` 버튼을 사용자가 클릭했을 때만 실행합니다.

즉, **검색 1클릭 → 조건 일치 결과 확인 → 신청 1클릭** 방식입니다.

## 설치

압축 파일의 `AutoMPlusFinder` 폴더를 아래 경로에 넣습니다.

```text
World of Warcraft\_retail_\Interface\AddOns\AutoMPlusFinder
```

설치 후 폴더 구조는 다음과 같아야 합니다.

```text
AutoMPlusFinder/
├─ AutoMPlusFinder.toc
├─ AutoMPlusFinder.lua
└─ README.md
```

게임을 완전히 종료한 뒤 다시 실행하거나, 이미 실행 중이라면 애드온 설치 후 재시작하세요.

## 사용법

1. 게임에서 `/ampf` 입력
2. 최소/최대 단수 지정
3. 신청할 역할 선택
4. 원하는 던전 선택
5. `검색 / 갱신` 클릭
6. 조건에 맞는 결과가 나타나면 각 행의 `신청` 클릭

파티 찾기 기본 UI에서 직접 검색한 경우에도 `LFG_LIST_SEARCH_RESULTS_RECEIVED` 이벤트를 받아 현재 검색 결과를 다시 필터링합니다.

## 명령어

```text
/ampf
/ampf show
/ampf hide
/ampf reset
/ampf help
```

## 시즌 2 던전 처리 방식

던전 이름이나 Activity ID를 소스에 고정하지 않습니다. `C_LFGList.GetAvailableActivities()`와 `C_LFGList.GetActivityInfoTable()`을 이용해서 **현재 클라이언트가 제공하는 Current Season Mythic+ 던전 목록**을 동적으로 구성합니다.

따라서 한국어 클라이언트에서는 한국어 던전명이 그대로 표시되며, 단순 Activity ID 변경에 대해서도 하드코딩 방식보다 안전합니다.

## 버전

- Addon: 1.0.0
- WoW Retail Interface: `120100`
