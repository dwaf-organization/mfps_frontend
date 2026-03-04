# MFPS Refactoring Rules

이 문서는 `/Users/suhyeon/Desktop/dwaf_repository/mfps-refactor/mfps-fe` 프로젝트에서
새 파일을 만들거나 기존 코드를 리팩터링할 때 항상 적용할 기준이다.

목표:

- 파일명, 클래스명, 변수명을 일관되게 유지한다.
- 블루투스 연결 코드, 데이터 수신 코드, 현재 퍼블리싱 UI를 깨지 않으면서 구조를 정리한다.
- 새 기능을 추가해도 기존 코드 스타일과 충돌하지 않게 한다.

## 1. 절대 원칙

- 블루투스 관련 동작은 유지한다.
- 데이터 조회/수신 로직은 유지한다.
- 현재 화면 퍼블리싱(UI 레이아웃, 구성, 시각적 출력)은 유지한다.
- 리팩터링은 동작 변경이 아니라 구조/가독성 개선을 우선한다.
- 공통 로직 분리는 가능하지만, API 경로/응답 키/블루투스 프로토콜은 임의 변경하지 않는다.

## 2. 파일명 규칙

- 모든 Dart 파일명은 `snake_case.dart`를 사용한다.
- 대문자가 들어간 파일명은 사용하지 않는다.
- 오타가 있는 파일명은 바로잡는다.

예시:

- `url_config.dart`
- `login_page.dart`
- `ward_select_page.dart`
- `dashboard_page.dart`
- `settings_dialog.dart`
- `week_meal_table.dart`

사용 금지 예시:

- `urlConfig.dart`
- `Settings_Dialog.dart`
- `week_mael_table.dart`

## 3. 화면 파일 규칙

- 화면 단위 파일은 가능하면 `*_page.dart`를 사용한다.
- 목록 화면은 `*_list.dart`를 사용한다.
- 상세 화면은 `*_detail.dart`를 사용한다.
- 다이얼로그 파일은 `*_dialog.dart`를 사용한다.
- 카드/타일/헤더 등 UI 조각은 `*_card.dart`, `*_tile.dart`, `*_header.dart` 같은 의미 기반 이름을 사용한다.

예시:

- `patient_detail_page.dart`
- `patient_add_dialog.dart`
- `room_card.dart`
- `top_header.dart`

## 4. 폴더 구조 규칙

- 기능 기준으로 `features/` 아래에 모은다.
- 앱 공통 구성은 `app/` 아래에 둔다.
- API 통신은 `api/` 아래에 둔다.
- 저장소/보안 키 관련 코드는 `storage/` 또는 루트 공통 파일로 둔다.

기본 구조:

```text
lib/
├── api/
├── app/
├── features/
│   ├── auth/
│   ├── dashboard/
│   ├── meal/
│   └── ...
├── storage/
├── storage_keys.dart
├── url_config.dart
└── main.dart
```

세부 규칙:

- 기능 내부에서 파일이 많아지면 `pages/`, `widgets/`, `services/`, `dialogs/`로 세분화한다.
- 블루투스 로직은 `services/` 아래에 유지한다.
- 화면 퍼블리싱용 위젯은 `widgets/`에 둔다.

## 5. 클래스명 규칙

- 클래스명은 모두 `PascalCase`를 사용한다.
- 화면 클래스는 `Page` 접미사를 우선 사용한다.
- 다이얼로그 클래스는 `Dialog` 접미사를 사용한다.
- 서비스 클래스는 `Manager`, `Service`, `Api` 같은 역할 기반 접미사를 사용한다.

예시:

- `LoginPage`
- `WardSelectPage`
- `DashboardPage`
- `SettingsDialog`
- `BluetoothConnectionManager`
- `HospitalStructureApi`

사용 금지 예시:

- `Urlconfig`
- 역할이 불분명한 축약 클래스명

## 6. 변수명 규칙

- 변수명은 `camelCase`를 사용한다.
- private 필드만 `_` prefix를 사용한다.
- 의미 없는 축약형은 사용하지 않는다.

좋은 예시:

- `hospitalIdController`
- `passwordController`
- `selectedWard`
- `selectedWardJson`
- `hospitalCode`
- `hospitalPassword`
- `wardItems`
- `floorItems`
- `_frontUrl`
- `_isLoading`
- `_selectedWard` 

피해야 할 예시:

- `idCtrl`
- `pwCtrl`
- `m`
- `w`
- `e`
- `j`
- `res`
- `next`
- `_front_url`

예외:

- `for (final item in items)`처럼 의미가 명확한 짧은 이름은 허용
- 콜백 내부에서도 `e`, `m`, `d`, `w` 같은 한 글자 변수는 가급적 금지

## 7. 상수명 규칙

- `static const` private 상수는 의미 기반 이름으로 작성한다.
- 저장소 키 이름은 "무엇을 저장하는 키인지" 드러나야 한다.

좋은 예시:

- `_hospitalCodeStorageKey`
- `_selectedWardStorageKey`
- `_baseUrl`

피해야 할 예시:

- `_kHospitalCode`
- `_kSelectedWardJson`
- `_base`

## 8. 함수명 규칙

- 함수명은 동사 + 목적어 중심으로 작성한다.
- 이벤트 핸들러는 `_handle...`
- 조회 함수는 `_load...`, `fetch...`, `get...`
- UI 조립 함수는 `_build...`
- 표시 함수는 `_show...`

예시:

- `_handleLogin()`
- `_loadStoredHospitalCode()`
- `_loadWards()`
- `_showEditFloorSheet()`
- `_showAddWardSheet()`
- `_buildRoomGrid()`

피해야 할 예시:

- `doIt()`
- `test1()`
- `tmp()`
- 의미가 모호한 `getData()` 남용

추가 규칙:

- 정말 범용적인 경우가 아니면 `getData()`보다 `_loadWardList()`, `_loadPatientList()`처럼 구체적으로 쓴다.

## 9. 상태 변수 규칙

- 불리언 상태는 `_is...`, `_has...`, `_can...` 형태를 우선 사용한다.

예시:

- `_isLoading`
- `_isBluetoothConnected`
- `_hasSelectedWard`

- 선택 상태는 `selected...` 또는 `_selected...`

예시:

- `selectedFloorStCode`
- `_selectedWard`

## 10. Controller / 입력 관련 규칙

- `TextEditingController`는 입력 의미가 드러나야 한다.

예시:

- `hospitalIdController`
- `passwordController`
- `searchKeywordController`
- `remarkController`

- `Ctrl` 같은 축약은 새 코드에서 사용하지 않는다.

## 11. JSON / API 응답 변수 규칙

- `Map<String, dynamic>`를 써야 할 때도 변수명은 의미를 드러낸다.

예시:

- `decodedResponse`
- `responseData`
- `selectedWardMap`
- `patientProfileMap`

피해야 할 예시:

- `m`
- `j`
- `decoded`

단, 아주 짧은 범위에서 이미 의미가 충분한 경우만 제한적으로 허용한다.

## 12. 반복문 / 콜렉션 변수 규칙

- 반복문 변수는 컬렉션 의미와 맞춰서 작성한다.

예시:

- `for (final ward in wards)`
- `for (final floor in floors)`
- `for (final patient in patients)`
- `for (final part in parts)`

- 새 리스트를 만들 때 `next`보다 목적이 드러나는 이름을 사용한다.

예시:

- `wardItems`
- `floorItems`
- `filteredPatients`
- `updatedRooms`

## 13. import 규칙

- 루트 공통 파일은 가능하면 `package:mfps/...` import를 사용한다.
- 같은 기능 내부의 작은 위젯/파일은 상대경로 import를 사용해도 된다.

권장:

```dart
import 'package:mfps/url_config.dart';
import 'package:mfps/storage_keys.dart';
import 'package:mfps/api/http_helper.dart';
```

허용:

```dart
import 'auth_shared_widgets.dart';
import 'widgets/top_header.dart';
```

지양:

```dart
import '../../../../url_config.dart';
```

## 14. UI 리팩터링 규칙

- 현재 퍼블리싱 결과가 바뀌지 않도록 한다.
- 큰 위젯은 `_build...()` 함수 또는 별도 위젯 파일로 분리한다.
- 분리 시에도 색상, spacing, typography, 위젯 구조는 그대로 유지한다.
- UI 분리는 "가독성 향상"이 목적이지 "디자인 변경"이 목적이 아니다.

## 15. 블루투스 코드 규칙

- `BluetoothConnectionManager`의 연결 흐름은 유지한다.
- UUID, 디바이스 연결 순서, 타이머, 수신 파싱 로직은 함부로 변경하지 않는다.
- 블루투스 관련 리팩터링은 아래 범위만 우선 허용한다.

허용:

- 파일 분리
- 함수명 개선
- 변수명 개선
- 주석 보강
- 중복 코드 정리

금지:

- 프로토콜 포맷 변경
- API 전송 payload 변경
- 수신 데이터 처리 순서 변경
- 타이머 시작 타이밍 변경

## 16. 데이터/API 코드 규칙

- API 경로 문자열은 기존과 동일하게 유지한다.
- 백엔드 응답 키(`hospital_code`, `hospital_st_code` 등)는 절대 임의 변경하지 않는다.
- 프론트 변수명만 읽기 쉽게 바꾼다.

예시:

- 응답 키: `hospital_st_code`
- 프론트 변수명: `hospitalStCode`

## 17. 새 파일 생성 시 템플릿 기준

새 화면 파일 기본 형태:

```dart
import 'package:flutter/material.dart';

class SamplePage extends StatefulWidget {
  const SamplePage({super.key});

  @override
  State<SamplePage> createState() => _SamplePageState();
}

class _SamplePageState extends State<SamplePage> {
  bool _isLoading = false;

  Future<void> _loadPageData() async {}

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SizedBox.shrink(),
    );
  }
}
```

새 다이얼로그 파일 기본 형태:

```dart
import 'package:flutter/material.dart';

class SampleDialog extends StatelessWidget {
  const SampleDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return const Dialog(
      child: SizedBox.shrink(),
    );
  }
}
```

## 18. 리팩터링 체크리스트

파일을 만들거나 수정할 때 아래 순서대로 확인한다.

1. 파일명이 `snake_case`인가
2. 클래스명이 역할 기반 `PascalCase`인가
3. 변수명이 축약 없이 의미를 드러내는가
4. `_front_url` 같은 혼합 네이밍이 없는가
5. 저장소 키 상수가 의미 기반 이름인가
6. 블루투스/데이터 수신 로직을 건드리지 않았는가
7. UI 퍼블리싱이 바뀌지 않았는가
8. 공통 루트 파일 import가 과도한 상대경로가 아닌가
9. 함수명이 동작 목적을 명확히 설명하는가
10. 변경 후 `flutter analyze` 기준 에러가 없는가

## 19. 이 프로젝트에서 우선 적용할 스타일

이 프로젝트에서는 앞으로 아래 스타일을 기본값으로 사용한다.

- 파일명: `snake_case`
- 클래스명: `PascalCase`
- 변수명: `camelCase`
- private 필드: `_camelCase`
- 화면 파일: `*_page.dart`
- 다이얼로그 파일: `*_dialog.dart`
- 공통 설정 파일: `url_config.dart`
- 라우터 함수: `buildAppRouter()`

## 20. 적용 범위

이 문서의 규칙은 아래 작업에 모두 적용한다.

- 새 화면 생성
- 새 컴포넌트 생성
- 새 다이얼로그 생성
- 새 서비스 생성
- 기존 파일 리팩터링
- 변수명 정리
- 파일 이동/분리

단, 아래는 예외다.

- 백엔드 응답 키 자체
- 블루투스 장치 통신 포맷
- 이미 동작 중인 API 스펙

