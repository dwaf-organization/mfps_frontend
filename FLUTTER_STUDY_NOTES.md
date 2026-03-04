# Flutter Study Notes For MFPS

이 문서는 `/Users/suhyeon/Desktop/dwaf_repository/mfps-refactor/mfps-fe` 프로젝트를 기준으로
Flutter를 공부할 때 필요한 핵심 개념을 정리한 문서다.

## 1. 이 프로젝트는 어떤 앱인가

- Flutter로 만든 의료/병동 관리 앱
- 로그인, 병동 선택, 대시보드, 환자 상세, 케어 입력, 식단/실금, 블루투스 기능 포함
- UI만 있는 앱이 아니라 API, 로컬 저장소, 블루투스까지 같이 들어간 실무형 구조

## 2. Flutter 기본 개념

### 위젯 기반

Flutter는 화면의 거의 모든 것을 `Widget`으로 만든다.

- `Text`
- `Row`
- `Column`
- `Padding`
- `Scaffold`

예시:

```dart
return Scaffold(
  appBar: AppBar(title: const Text('제목')),
  body: const Center(
    child: Text('안녕하세요'),
  ),
);
```

### `StatelessWidget` vs `StatefulWidget`

`StatelessWidget`

- 상태가 없는 UI
- 고정된 텍스트, 카드, 라벨 등에 사용

`StatefulWidget`

- 상태가 바뀌는 UI
- 선택 상태, 입력값, 로딩, 탭, 리스트 갱신 등에 사용

예시:

```dart
class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$count'),
        ElevatedButton(
          onPressed: () {
            setState(() {
              count++;
            });
          },
          child: const Text('증가'),
        ),
      ],
    );
  }
}
```

### `build()`

- 화면을 그리는 함수
- 상태가 바뀌면 다시 호출됨

### `setState()`

- 화면 상태가 바뀌었다고 Flutter에 알림

```dart
setState(() {
  _isLoading = true;
});
```

### `BuildContext`

주요 사용처:

- `Navigator`
- `showDialog`
- `showModalBottomSheet`
- `Theme.of(context)`
- `MediaQuery.of(context)`

## 3. Dart 문법 기초

### 변수

```dart
String name = '홍길동';
int age = 20;
bool isLoading = false;
```

### `final` / `const`

```dart
final now = DateTime.now();
const title = '로그인';
```

### nullable

```dart
String? name;
int? selectedFloorCode;
```

### 조건문

```dart
if (hospitalCode == null) {
  return;
}
```

### 반복문

```dart
for (final ward in wards) ...[
  Text(ward.categoryName),
]
```

## 4. 이 프로젝트의 폴더 구조

```text
lib/
├── api/
├── app/
├── features/
│   ├── auth/
│   ├── dashboard/
│   ├── meal/
│   └── calender/
├── storage/
├── storage_keys.dart
├── url_config.dart
└── main.dart
```

### 역할

- `main.dart`: 앱 시작점
- `app/`: 앱 설정, 라우터, 테마
- `api/`: HTTP 통신
- `features/`: 실제 화면/기능
- `storage_keys.dart`: 저장소 키 상수
- `url_config.dart`: 서버 URL 설정

## 5. 화면 이동 구조

`go_router` 사용.

대표 경로:

- `/login`
- `/ward-select`
- `/dashboard`

예시:

```dart
context.go('/dashboard');
```

## 6. 이 프로젝트로 Flutter 공부할 때 추천 순서

1. [main.dart](/Users/suhyeon/Desktop/dwaf_repository/mfps-refactor/mfps-fe/lib/main.dart)
2. [app.dart](/Users/suhyeon/Desktop/dwaf_repository/mfps-refactor/mfps-fe/lib/app/app.dart)
3. [router.dart](/Users/suhyeon/Desktop/dwaf_repository/mfps-refactor/mfps-fe/lib/app/router.dart)
4. [login_page.dart](/Users/suhyeon/Desktop/dwaf_repository/mfps-refactor/mfps-fe/lib/features/auth/login_page.dart)
5. [ward_select_page.dart](/Users/suhyeon/Desktop/dwaf_repository/mfps-refactor/mfps-fe/lib/features/auth/ward_select_page.dart)
6. [dashboard_page.dart](/Users/suhyeon/Desktop/dwaf_repository/mfps-refactor/mfps-fe/lib/features/dashboard/dashboard_page.dart)
7. [patient_care_page.dart](/Users/suhyeon/Desktop/dwaf_repository/mfps-refactor/mfps-fe/lib/features/dashboard/pages/patient_care_page.dart)
8. [meal_tab.dart](/Users/suhyeon/Desktop/dwaf_repository/mfps-refactor/mfps-fe/lib/features/meal/meal_tab.dart)
9. [month_calendar.dart](/Users/suhyeon/Desktop/dwaf_repository/mfps-refactor/mfps-fe/lib/features/calender/widget/month_calendar.dart)
10. [bluetooth_connection_manager.dart](/Users/suhyeon/Desktop/dwaf_repository/mfps-refactor/mfps-fe/lib/features/dashboard/services/bluetooth_connection_manager.dart)

## 7. 화면별로 배울 수 있는 것

### 로그인

파일:

- [login_page.dart](/Users/suhyeon/Desktop/dwaf_repository/mfps-refactor/mfps-fe/lib/features/auth/login_page.dart)

배울 것:

- `TextEditingController`
- 입력 처리
- 로딩 상태
- API 호출 후 라우팅

### 병동 선택

파일:

- [ward_select_page.dart](/Users/suhyeon/Desktop/dwaf_repository/mfps-refactor/mfps-fe/lib/features/auth/ward_select_page.dart)

배울 것:

- 리스트 렌더링
- 선택 상태
- 바텀시트
- 키보드 대응
- 버튼 상태 스타일

### 환자 케어 입력

파일:

- [patient_care_page.dart](/Users/suhyeon/Desktop/dwaf_repository/mfps-refactor/mfps-fe/lib/features/dashboard/pages/patient_care_page.dart)

배울 것:

- `TabController`
- `TabBarView`
- 커스텀 UI 배치
- 바텀시트 입력
- 페이지네이션
- 차트

### 식단

파일:

- [meal_tab.dart](/Users/suhyeon/Desktop/dwaf_repository/mfps-refactor/mfps-fe/lib/features/meal/meal_tab.dart)
- [week_meal_table.dart](/Users/suhyeon/Desktop/dwaf_repository/mfps-refactor/mfps-fe/lib/features/meal/week_meal_table.dart)

배울 것:

- 표 UI
- 월 선택
- 날짜별 상태 저장

### 실금

파일:

- [month_calendar.dart](/Users/suhyeon/Desktop/dwaf_repository/mfps-refactor/mfps-fe/lib/features/calender/widget/month_calendar.dart)
- [incontinence_bottom_sheet.dart](/Users/suhyeon/Desktop/dwaf_repository/mfps-refactor/mfps-fe/lib/features/calender/widget/incontinence_bottom_sheet.dart)

배울 것:

- 달력 구성
- 날짜 선택
- 바텀시트 safe area

### 블루투스

파일:

- [bluetooth_connection_manager.dart](/Users/suhyeon/Desktop/dwaf_repository/mfps-refactor/mfps-fe/lib/features/dashboard/services/bluetooth_connection_manager.dart)

배울 것:

- 비동기 처리
- 스트림
- 디바이스 연결
- 측정 데이터 수신/전송

## 8. 이 프로젝트에서 자주 보는 패턴

### 상태값

```dart
bool _isLoading = false;
WardItem? _selectedWard;
```

### 입력 컨트롤러

```dart
final hospitalIdController = TextEditingController();
final passwordController = TextEditingController();
```

반드시 `dispose()`에서 정리:

```dart
@override
void dispose() {
  hospitalIdController.dispose();
  passwordController.dispose();
  super.dispose();
}
```

### 바텀시트

```dart
showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  builder: (_) => const SomeBottomSheet(),
);
```

### 다이얼로그

```dart
showDialog(
  context: context,
  builder: (context) => const AlertDialog(),
);
```

### SafeArea / MediaQuery

```dart
final bottomInset = MediaQuery.of(context).padding.bottom;
final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
```

정리:

- `padding.bottom`: 기기 하단 safe area
- `viewInsets.bottom`: 키보드 높이

## 9. API 호출 구조

이 프로젝트는 `HttpHelper`를 많이 사용한다.

```dart
final decoded = await HttpHelper.postJson(uri, {
  'hospital_id': hospitalId,
  'hospital_password': hospitalPassword,
});
```

흐름:

1. `Uri.parse(...)`
2. `HttpHelper.getJson/postJson`
3. `decoded['code']` 확인
4. 성공 시 상태 반영
5. 실패 시 `SnackBar` 또는 예외 처리

## 10. 로컬 저장소

`FlutterSecureStorage` 사용.

예:

```dart
await _storage.write(
  key: StorageKeys.selectedWardName,
  value: wardName,
);
```

용도:

- 로그인 정보 유지
- 병동 선택 정보 유지

## 11. 이 프로젝트의 현재 코드 스타일

- 파일명: `snake_case`
- 클래스명: `PascalCase`
- 변수명: `camelCase`
- private 필드: `_camelCase`
- 화면 파일: `*_page.dart`
- 다이얼로그 파일: `*_dialog.dart`

관련 규칙 문서:

- [REFACTORING_RULES.md](/Users/suhyeon/Desktop/dwaf_repository/mfps-refactor/mfps-fe/REFACTORING_RULES.md)

## 12. 공부할 때 직접 해보면 좋은 연습

쉬운 연습:

- 버튼 텍스트 바꾸기
- 색상 바꾸기
- 간격 조정하기

중간 연습:

- 새 버튼 추가
- 바텀시트 필드 추가
- 로그 컬럼 추가

어려운 연습:

- 새 탭 추가
- 실제 API 연결
- DTO 모델 분리
- 블루투스 데이터 화면 반영

## 13. 핵심 요약

- Flutter는 위젯 조합으로 화면을 만든다
- 상태가 바뀌면 `setState()`로 다시 그린다
- 라우터로 화면을 이동한다
- 입력은 `TextEditingController`로 관리한다
- 태블릿 대응은 `SafeArea`, `MediaQuery`가 중요하다
- 이 프로젝트는 UI, API, 저장소, 블루투스를 같이 공부하기 좋다

