# #958 admin 보안 점검 — 비밀번호 변경 주기·세션 타임아웃·업로드 상한 — 구현 계획 (최종 확정본)

세션 형태: **경계 작업(DB 스키마) + 동작 변경**. `sgt_admin` 에 컬럼을 더하는 Flyway V3 와 로그인 흐름 변경(만료 시 강제 변경)이 한 덩어리이고, 세션 타임아웃·multipart 상한은 yml 한 줄짜리 동작 변경이다.
**PR 분할 확정(2개)**: PR-A = T1~T6(비밀번호 변경 주기, 스키마 포함. T4 는 삭제됨), PR-B = T7~T8(세션 30분 명시 + multipart 상한 `max-file-size: 100MB` / `max-request-size: 500MB`). PR-B 는 PR-A 에 의존하지 않는다. **이슈 #958 은 PR-B 머지 후 close 한다.**
근거 자료: 이슈 #958 본문과 "이슈 검토 결과 — 범위 정정" 댓글, triage 판정(2026-11-08, develop `e070c03ed`), GATE 1 사용자 결정(2026-11-08), plan-review-1 반영(2026-11-08), plan-review-2 반영 + GATE 1 계획 승인(2026-11-08), 읽은 CLAUDE.md: `/CLAUDE.md`, `sgt-admin/CLAUDE.md`

범위 밖(결정으로 제외): 비밀번호 복잡도 규칙(#985 로 완료, 서버 상수와 화면 JS 2곳 그대로), remember-me(유효기간 15일, 그리고 아래 "현재 상태"에 적은 자동 로그인 미연결 문제), 라이선스 업로드(코드에서 256KB 제한), 보안정책 테이블(`PolicyType`) 확장, 비밀번호 이력 관리(이전 N개 재사용 금지 — 현재 비밀번호와 같은 값만 거절한다).

## 현재 상태

- **스키마**: `sgt-admin/src/main/resources/db/migration/` 에는 `V1__schema.sql`, `V2__seed.sql` 두 개뿐이다. 그래서 다음 번호는 **V3**다. 최신 출시 태그는 `v3.10.0` 이다. `sgt_admin` 테이블(`V1__schema.sql:4-26`)에는 비밀번호 변경 시각 컬럼이 없다. 컬럼 주석은 `COMMENT ON COLUMN` 으로 단다(`V1__schema.sql:28-43`). 시드 관리자 `admin` 은 `V2__seed.sql:3` 에서 들어간다.
- **엔티티**: `domain/Admin.java:28-100` 에도 변경 시각 필드가 없다. `updatePassword(String)`(`:146`)는 해시만 바꾼다. 같은 모양의 판정 메서드로 `isLockExpired()`(`:245`)가 있다. `isSuperAdmin()`(`:206-208`)은 `role == SUPER_ADMIN` 이다.
- **비밀번호 쓰기 경로는 하나다**: `PUT /api/v1/admins/{adminId}/password`(`rest/AdminRestController.java:92-103`) → `AdminService.updatePassword`(`service/AdminService.java:308-316`) → `Admin.updatePassword`. `AdminService.updatePassword` 는 `getAdminById` → `BCryptUtil.checkPw(oldPassword, admin.getPassword())` 불일치 시 `SgtException`(`:311-312`) → `admin.updatePassword(encodePassword(newPassword))`(`:314`) 순서다. 복잡도 검사는 `encodePassword`(`:473-478`) 안에 있다. **새 비밀번호가 현재 비밀번호와 같은지는 아무 데서도 보지 않는다**(화면 JS `config-form.html:139-161` 도 새 값과 확인값만 비교). 생성 경로는 `addAdmin`(`:386`)과 `addAdminWithRole`(`:422`) 두 곳이고, 둘 다 `Admin.builder()` 를 쓴다. SCIM 은 `changePassword.supported=false` 라 admin 비밀번호를 건드리지 않는다(`openapi/controller/ScimController.java:67-69`).
- **BCrypt 유틸**: `common/utils/BCryptUtil.java:36` `public static boolean checkPw(String password, String hashed)` — 내부는 `org.springframework.security.crypto.bcrypt.BCrypt.checkpw`. `AdminService` 는 이미 import 해서 쓴다(`AdminService.java:5`, `:289`, `:311`).
- **SgtException → 400**: `new SgtException(String)`(`common/exception/SgtException.java:32`)의 기본 상태는 `BAD_REQUEST`(`:16`)이고, `RestControllerExceptionHandler`(`common/exception/handler/RestControllerExceptionHandler.java:109-117`)가 `e.getHttpStatus()` 로 응답한다.
- **로그인 흐름**: 폼 로그인과 2FA 는 모두 `security/AuthenticationSuccessHandler.completeFinalLogin`(`:141-192`)에서 끝난다. 이 메서드는 감사 로그를 쓰려고 try 블록 안에서 `adminService.getAdmin(adminName)` 를 부르고(`:152`), 실패하면 로그만 남기고 로그인을 계속한다(`:164-166`). 리다이렉트 대상은 `:178-189` 에서 정한다. `setAlwaysUseDefaultTargetUrl(true)`(`:188`)이므로 저장된 요청은 남지 않는다. 폼 인증은 `IdPasswordAuthenticationProvider` 가 맡으므로 `UserDetailsService` 를 거치지 않는다.
- **현재 사용자 판정**: `SecurityUtil.getCurrentAdminId`(`security/SecurityUtil.java:46-57`)는 `adminService.getAdmin(username).getId()` 를 쓰고, 예외 시 null. `isCurrentUser`(`:67-70`)·`isSuperAdmin`(`:78-89`)도 `getAdmin(username)` 을 쓴다. `AdminRestController.hasPermissionToModify`(`:262-274`)는 이 둘을 부른다. 즉 이 경로는 `getAdminDto` 가 아니라 **`getAdmin(String)`** 에 의존한다.
- **remember-me 는 쿠키를 발급만 하고 자동 로그인은 하지 않는다(기존 결함, 범위 밖)**: 메인 체인(`common/conf/SecurityConfig.java:271-307`)에 `.rememberMe(...)` 가 없다. `src/main/java` 전체에서 `RememberMeAuthenticationFilter`·`autoLogin` grep 결과는 0건이다. `rememberMeServices()` 빈(`SecurityConfig.java:363-367`)은 성공 핸들러의 `loginSuccess`(`AuthenticationSuccessHandler.java:169-170`, 쿠키 발급)에서만 쓰인다. `UserDetailsServiceImpl` 도 이 빈의 생성자 인자(`SecurityConfig.java:365`)로만 쓰이므로, 실제로는 호출되지 않는다. 기존 `RememberMeTest.accessWithRememberMeCookie`(`:75-104`)는 로그인한 **같은 세션**으로 `/dashboard` 를 요청하므로 자동 로그인을 증명하지 못한다. 결론: 쿠키만으로는 인증되지 않으므로, 강제 변경을 remember-me 로 우회할 길이 지금은 없다.
- **요청마다 도는 기존 필터**: `security/AccessControlFilter.java:33-59`(IP 허용 목록)가 메인 체인에 `addFilterBefore(accessControlFilter, UsernamePasswordAuthenticationFilter.class)` 로 걸려 있다(`SecurityConfig.java:276`). `/openapi/`·`/config/` 는 여기서 건너뛴다(`:38`, `request.getRequestURI()` 기준 `:37` — context-path 를 고려하지 않는 기존 패턴). IP 검사 예외는 catch 해서 허용한다(`:53-56`).
- **변경 화면**: 독립 페이지가 없다. `/settings`(`controller/MainController.java:102-115`)의 모달 `#pwd-change-modal`(`templates/settings/modal/config-form.html:4-196`)이 그 역할을 한다. 모달은 현재 비밀번호를 확인(`/password/verify`)한 뒤 변경(`/password`)하고, 성공하면 `/settings` 로 다시 이동한다(`:183`). 공통 레이아웃(`templates/layouts/layout.html:5`)은 `fragments/config :: csrfConfig`(`fragments/config.html:149-158`)를 넣어 `_csrf`/`_csrf_header` meta 를 렌더하고 `$(document).ajaxSend` 로 **CSRF 를 헤더로** 보낸다(`:154-158`). 로그인 화면(`login.html` → `layouts/authLayout.html`)은 `csrfConfig` 를 넣지 않고 `_csrf` hidden input 만 렌더한다(`login.html:22-23`). CSRF 저장소는 `HttpSessionCsrfTokenRepository`(`SecurityConfig.java:273`, 기본 헤더명 `X-CSRF-TOKEN`). **대상 화면 자체가 AJAX 를 부른다** — `settings.html` 과 `settings/modal/config-form.html` 을 grep 한 결과는 아래와 같다.

  | 호출 | 위치 | 언제 |
  |---|---|---|
  | `GET /api/v1/admins/{id}/2fa/status` | `settings.html:209-210`, `config-form.html:395-396` | 화면 로드 시 배지 표시, 2FA 모달 열 때 |
  | `POST /api/v1/admins/{id}/password/verify` | `config-form.html:113-114` | 비밀번호 변경 모달 |
  | `PUT /api/v1/admins/{id}/password` | `config-form.html:176-177` | 비밀번호 변경 모달 |
  | `GET /api/v1/admins/{id}/2fa/qrcode` (img) | `config-form.html:437` | 2FA 모달(비활성 상태) |
  | `POST /api/v1/admins/{id}/2fa/enable` | `config-form.html:469-470` | 2FA 모달 |
  | `POST /api/v1/admins/{id}/2fa/disable` | `config-form.html:517-518` | 2FA 모달 |
  | `PUT /api/v1/admins/{id}` | `settings.html:183-185` | 내 정보 수정 버튼 |

  2FA 4개 경로는 `rest/TwoFactorAuthRestController.java:29`(`/api/v1/admins/{adminId}/2fa`) 아래에 있고, 본인 또는 SUPER_ADMIN 만 허용하는 검사가 이미 있다(`:44-56`).
- **세션**: `server.servlet.session.timeout` 은 admin yml 4종(`application.yml`, `-dev`, `-docker`, `-local`)과 `src/test/resources/application-test.yml` 어디에도 없다. Boot 기본값 30분이 그대로 적용된다. 관련 설정은 `maximumSessions(1)` 와 `expiredUrl("/login?expired")`(`SecurityConfig.java:301-306`)이다.
- **multipart**: `application.yml:24-27` 에 `max-file-size: 1GB`, `max-request-size: 10GB` 가 있다. 대상 4경로는 `rest/ResourceRestController.java` 의 `POST ""`(`:71-73`), `POST /batch`(`:99-121`, `@RequestPart("file")`, `resources.batch-path`(`:58-59`)에 저장 후 `resourceBatchService.handleBatchFile`), `POST /bulk`(`:161-162`, `MultipartFile[]`, `resourceService.addResources`), `PUT /{resourceId}`(`:181-184`, 파일 선택)이다. 테스트 프로파일의 `resources.batch-path` 는 `./data/resources/batch`(`application-test.yml:67`)다. 상한 초과 처리는 `RestControllerExceptionHandler.java:92-100`(400 `NOT_VALID_PARAMETER`, `@RestControllerAdvice(basePackages="com.initech.sgt.rest")`)과 `ControllerExceptionHandler.java:37-48`(413 error 뷰)에 있다. 두 클래스 모두 `${spring.servlet.multipart.max-file-size}` 를 메시지에 쓴다. 화면 쪽 크기 검사는 없다(templates·static/js grep 결과 0건).
- **helm**: `admin.env` 의 임의 키는 그대로 env 로 렌더된다(`helm/templates/admin.yaml:140`). 그래서 `SPRING_SERVLET_MULTIPART_MAX_FILE_SIZE` 같은 relaxed binding 오버라이드에 **새 knob 이 필요 없다**. 리소스 PVC 기본값은 5Gi(`helm/values.yaml:286`)이고, `/tmp` emptyDir 에는 sizeLimit 이 없다(`helm/templates/admin.yaml:351-352`).
- **테스트 기반**: H2 는 `ddl-auto` 에 `src/test/resources/db/data.sql` 를 더해 쓴다. 이 파일에는 `sgt_admin` INSERT 가 **없다**(grep 0건). 그래서 data.sql 은 바꿀 필요가 없다. 로그인 흐름 MockMvc 의 참조는 `controller/RememberMeTest.java` 다(`AdminService` 를 `@MockitoBean` 으로 바꾸고 `getAdminDto("admin")`·`getAdmin("admin")` 를 stub(`:50-59`)한 뒤 `/auth/login` 을 POST). 실제 내장 Tomcat 테스트의 참조는 `common/conf/ConfigServerSecurityRealServerTest.java` 다(`RANDOM_PORT` + `@AutoConfigureTestRestTemplate` + 리다이렉트를 따라가지 않는 `TestRestTemplate`, 의존성 `spring-boot-resttestclient` 는 `build.gradle:179` 에 이미 있다). `AdminServiceTest` 는 `testAdminId`·`password = "initech12#"`(`:37-38`) 셋업을 쓰고, 기존 성공 케이스 `updatePassword`(`:82-91`)는 새 비밀번호 `initech34$` 로 현재와 다르므로 동일 비밀번호 거절을 넣어도 깨지지 않는다. 스키마 CI 게이트는 `scripts/check-admin-schema.sh` 다(출시 V 파일 불변 검사 + 엔티티와 V 파일 일치 검사). 이 게이트는 DEFAULT 차이는 비교하지 않고, `alter table … add column` 만 실패로 본다(`:84`).
- 빌드는 Spring Boot `4.1.2` 다(`sgt-admin/build.gradle:12`).

## 변경 파일 목록

| 파일 | 변경 | 참조 구현 |
|---|---|---|
| `sgt-admin/src/main/resources/db/migration/V3__admin_password_changed_at.sql` | 신규. nullable 컬럼, DEFAULT, 주석 | `V1__schema.sql:16-43`(TIMESTAMP NULL, COMMENT ON COLUMN) |
| `sgt-admin/src/main/java/com/initech/sgt/domain/Admin.java` | 필드 `passwordChangedAt`, 상수 90일, `isPasswordExpired()`, `updatePassword` 에서 시각 갱신 | `Admin.java:96-100`(nullable 시각 필드), `:245-251`(`isLockExpired`) |
| `sgt-admin/src/main/java/com/initech/sgt/service/AdminService.java` | `updatePassword` 에 현재 비밀번호와 같은 새 비밀번호 거절 한 줄 | `AdminService.java:311-312`(같은 메서드의 기존 비밀번호 불일치 거절) |
| `sgt-admin/src/main/java/com/initech/sgt/security/SecurityConstants.java` | 세션 키 상수와 변경 화면 URL 상수 | `SecurityConstants.java:9-13`, `:31-38` |
| `sgt-admin/src/main/java/com/initech/sgt/security/AuthenticationSuccessHandler.java` | 만료 시 세션 표시를 남기고 `/settings?passwordExpired` 로 리다이렉트 | 같은 파일 `:150-166`, `:178-189` |
| `sgt-admin/src/main/java/com/initech/sgt/security/AccessControlFilter.java` | 세션 표시가 있으면 허용 경로 밖 요청을 `contextPath + PASSWORD_CHANGE_URL` 로 리다이렉트 | 같은 파일 `:36-41`(경로 건너뛰기 패턴) |
| `sgt-admin/src/main/java/com/initech/sgt/rest/AdminRestController.java` | 본인 변경 성공 시 세션 표시 제거 | `:92-103`, `SecurityUtil.isCurrentUser`(`security/SecurityUtil.java:67`) |
| `sgt-admin/src/main/java/com/initech/sgt/controller/MainController.java` | `/settings` 모델에 `passwordExpired` 추가 | `MainController.java:102-115` |
| `sgt-admin/src/main/resources/templates/settings.html`, `templates/settings/modal/config-form.html` | 만료 안내 문구와 모달 자동 열기 | `config-form.html:62-72`(`th:inline="javascript"` + `$(document).ready`) |
| `sgt-admin/src/main/resources/application.yml` | `server.servlet.session.timeout: 30m`, multipart `100MB`/`500MB` | `application.yml:24-27`, `:52-54` |
| `sgt-admin/README.md` | "인증 및 권한" 절에 변경 주기·세션·업로드 상한·오버라이드 방법 | `README.md:656-666` |
| 테스트(신규) `src/test/java/com/initech/sgt/domain/AdminPasswordExpiryTest.java`, `src/test/java/com/initech/sgt/controller/PasswordExpiryFlowTest.java`, `src/test/java/com/initech/sgt/rest/ResourceUploadLimitRealServerTest.java` | 아래 태스크별 케이스 | `domain/ApikeyTest.java`, `controller/RememberMeTest.java`, `common/conf/ConfigServerSecurityRealServerTest.java` |
| 테스트(수정) `src/test/java/com/initech/sgt/service/AdminServiceTest.java`, `src/test/java/com/initech/sgt/common/conf/SecurityConfigTest.java` | 변경 시각 갱신 + 동일 비밀번호 거절 케이스, 세션·multipart 설정 고정 케이스 | 같은 파일 `:158-169`, `:18-24` |

**바꾸지 않는 파일**: `dto/AdminDto.java`(`LoginAdmin` 에 만료 필드를 넣지 않는다 — T3 는 `admin.isPasswordExpired()` 를 직접 부르고 T5 는 세션 표시를 쓰므로 쓰는 곳이 없다), `AdminService.getAdminDto(String)`/`getAdminDto(Long)`, `src/test/resources/db/data.sql`(`sgt_admin` 행이 없고 H2 컬럼은 `ddl-auto` 가 엔티티에서 만든다), `security/UserDetailsServiceImpl.java`(T4 삭제 사유 참조).

## 태스크

### T1. V3 마이그레이션 + 엔티티 필드  (선행: 없음 / 위험도: **높음** / PR-A)
- 이 태스크를 가장 앞에 둔 이유: V 파일을 잘못 만들면 모든 현장에서 admin 이 기동하지 못하고, 우리는 그 사실을 볼 수 없다.
- 파일: `V3__admin_password_changed_at.sql`(신규), `domain/Admin.java`
- 할 일:
  - V3 에는 다음 두 문장만 넣는다.
    - `ALTER TABLE sgt_admin ADD COLUMN IF NOT EXISTS password_changed_at TIMESTAMP NULL DEFAULT LOCALTIMESTAMP;`
    - `COMMENT ON COLUMN sgt_admin.password_changed_at IS '비밀번호 마지막 변경 일시';`
  - V3 에는 `BEGIN/COMMIT`, psql 메타 명령, `UPDATE` 를 넣지 않는다.
  - DEFAULT 를 둔 이유는 세 가지다.
    1. 기존 행이 **업그레이드 시각**으로 채워진다. PostgreSQL 은 ADD COLUMN 의 비휘발성 DEFAULT 를 ALTER 시점에 한 번 평가한다. 이것이 결정 "업그레이드 시점에 변경한 것으로 간주"를 그대로 구현한다.
    2. 롤링 업데이트 중 구 admin 파드가 컬럼을 빼고 INSERT 해도 생성 시각이 들어간다.
    3. 새 설치에서도 V2 시드의 `admin` 행이 설치 시각을 받는다. 따라서 즉시 강제는 없다.
  - `LOCALTIMESTAMP` 를 쓰는 이유: 컬럼 타입이 `TIMESTAMP`(타임존 없음)이고, 같은 테이블의 다른 시각 컬럼과 의미를 맞추기 위해서다.
  - `Admin` 에 `@Column(name = "password_changed_at") @Builder.Default private LocalDateTime passwordChangedAt = LocalDateTime.now();` 를 추가한다. 위치는 `lastFailedAttempt`(`:100`) 뒤다. 생성 경로 두 곳(`AdminService.java:386`, `:422`)은 builder 를 쓰므로 따로 고칠 필요가 없다.
  - 상수 `public static final Duration PASSWORD_MAX_AGE = Duration.ofDays(90);` 를 둔다(D3 확정).
  - `isPasswordExpired()` 를 추가한다. 규칙은 `passwordChangedAt != null && LocalDateTime.now().isAfter(passwordChangedAt.plus(PASSWORD_MAX_AGE))` 이다. NULL 은 "만료 아님"으로 본다. NULL 이 생기는 경우는 H2 나 명시적 null 뿐이고, 결정에 따라 즉시 강제는 하지 않는다.
  - `updatePassword(String)` 에서 `this.passwordChangedAt = LocalDateTime.now();` 를 설정한다.
- 참조: `V1__schema.sql:16-20`(TIMESTAMP NULL 컬럼), `:28-43`(COMMENT), `Admin.java:96-100`(nullable 시각 필드), `:245-251`(`isLockExpired` 판정 모양), `sgt-admin/CLAUDE.md` "Rules for a new V file"
- 테스트: `src/test/java/com/initech/sgt/domain/AdminPasswordExpiryTest.java`(신규, 순수 단위). 케이스:
  - (a) builder 로 만들면 만료가 아니다.
  - (b) `passwordChangedAt = now - 91일` 이면 만료다.
  - (c) `now - 89일` 이면 만료가 아니다.
  - (d) NULL 이면 만료가 아니다.
  - (e) `updatePassword()` 뒤에는 `passwordChangedAt` 이 갱신되어 만료가 아니다.
  - 과거 시각을 넣으려면 builder 의 `.passwordChangedAt(...)` 를 쓴다(`@AllArgsConstructor`·`@Builder` 가 이미 있다).
- 완료 조건:
  - V3 가 PostgreSQL 에서 적용된다.
  - 엔티티와 V 파일이 일치한다(`check-admin-schema.sh` ② 통과).
  - V1·V2 는 diff 0 이다.
- 검증:
  - `cd sgt-admin && JAVA_HOME=/opt/homebrew/opt/openjdk@21 ./gradlew test --tests 'AdminPasswordExpiryTest'` → 성공 시 `BUILD SUCCESSFUL in …`(실패 시 `AdminPasswordExpiryTest > … FAILED`).
  - 레포 루트에서 `(cd sgt-admin && JAVA_HOME=/opt/homebrew/opt/openjdk@21 ./gradlew bootJar) && scripts/check-admin-schema.sh` 를 실행한다(docker 와 origin 접근 필요). 성공 시 `① OK: v3.10.0 이후 출시된 V 파일 변경 없음` 과 `② OK: 엔티티가 요구하는 테이블·컬럼이 V 파일에 모두 있고, 새 타입·제약 차이 없음` 이 나온다.
  - `git diff --name-status v3.10.0 -- sgt-admin/src/main/resources/db/migration/` → `A	sgt-admin/src/main/resources/db/migration/V3__admin_password_changed_at.sql` 한 줄만 나온다.

### T2. 변경 시각 갱신 확인 + 현재 비밀번호와 같은 새 비밀번호 거절  (선행: T1 / 위험도: 낮음 / PR-A)
- 이 태스크가 필요한 이유: 거절이 없으면 만료 계정이 지금 비밀번호를 그대로 새 비밀번호로 넣어도 복잡도 검사를 통과하고 T1 이 `passwordChangedAt` 을 갱신한다. 비밀번호는 그대로인데 90일이 다시 시작되어 변경 주기가 무력화된다(plan-review-2 Important [70]).
- 파일: `service/AdminService.java`, `src/test/java/com/initech/sgt/service/AdminServiceTest.java`
- 할 일:
  - `AdminService.updatePassword`(`:308-316`)에서 기존 비밀번호 불일치 검사(`:311-312`) **바로 뒤**, `admin.updatePassword(encodePassword(...))`(`:314`) **앞**에 한 줄을 넣는다:
    `if (passwordUpdateRequest.getNewPassword() != null && BCryptUtil.checkPw(passwordUpdateRequest.getNewPassword(), admin.getPassword())) throw new SgtException("새 비밀번호는 현재 비밀번호와 달라야 합니다.");`
    - 시그니처: `BCryptUtil.checkPw(String password, String hashed)`(`common/utils/BCryptUtil.java:36`), 이미 import 되어 있다(`AdminService.java:5`).
    - null 가드는 `BCrypt.checkpw` 에 null 평문을 넘기지 않기 위해서다. null 새 비밀번호는 바로 다음 `encodePassword`(`:473-478`)가 기존처럼 복잡도 메시지로 거절한다.
    - `new SgtException(String)` 은 400 이다(`SgtException.java:16`, `:32`; `RestControllerExceptionHandler.java:109-117`). 화면은 기존 error 콜백으로 메시지를 보인다. 화면 JS 는 바꾸지 않는다.
    - 메서드 Javadoc 의 `@throws SgtException` 설명에 "새 비밀번호가 현재와 같은 경우"를 덧붙인다.
  - `LoginAdmin`·`fromEntity`·`getAdminDto(String)` 은 **바꾸지 않는다**(plan-review-2 Minor [70], 쓰는 곳 없음).
- 참조: `AdminService.java:311-312`(같은 메서드의 `checkPw` → `SgtException` 거절), `AdminServiceTest.java:158-169`(`updatePasswordRejectsWeakPassword` 셋업과 `assertThrows` 모양)
- 테스트: `AdminServiceTest.java` 에 케이스 두 개를 추가한다. 셋업은 `updatePasswordRejectsWeakPassword`(`:158-169`)와 같다(`@Transactional`, `testAdminId`, `password`).
  - (a) **변경 시각 갱신**: 호출 전 `LocalDateTime before = LocalDateTime.now()` → `updatePassword(testAdminId, new PasswordUpdateRequest(password, "initech34$", "initech34$"))` 성공 → `adminService.getAdminById(testAdminId).getPasswordChangedAt()` 이 `before` 이후(같거나 뒤)다.
  - (b) **동일 비밀번호 거절**: `new PasswordUpdateRequest(password, password, password)` → `assertThrows(SgtException.class, …)`, 메시지에 `"현재 비밀번호와 달라야"` 포함. 이어서 `getAdminById(testAdminId)` 의 비밀번호가 여전히 `BCryptUtil.checkPw(password, …)` 로 일치함을 단언한다(변경되지 않음).
- 완료 조건:
  - 비밀번호 변경이 성공하면 `password_changed_at` 이 그 시각으로 갱신된다.
  - 새 비밀번호가 현재 비밀번호와 같으면 400 `SgtException` 으로 거절되고 비밀번호·변경 시각이 바뀌지 않는다.
  - 기존 `updatePassword`·`notEqOldPassword`·`updatePasswordRejectsWeakPassword` 케이스가 그대로 통과한다.
- 검증: `cd sgt-admin && JAVA_HOME=/opt/homebrew/opt/openjdk@21 ./gradlew test --tests 'AdminServiceTest'` → `BUILD SUCCESSFUL in …`

### T3. 만료 시 변경 화면으로 강제 이동(로그인 성공 핸들러 + 기존 필터)  (선행: T1 / 위험도: **보통** / PR-A)
- 파일: `security/SecurityConstants.java`, `security/AuthenticationSuccessHandler.java`, `security/AccessControlFilter.java`, `rest/AdminRestController.java`
- 할 일:
  1. `SecurityConstants` 에 상수 두 개를 둔다.
     - `SESSION_PASSWORD_EXPIRED = "password-expired"`(세션 키 상수 묶음 `:9-13` 옆)
     - `PASSWORD_CHANGE_URL = "/settings?passwordExpired"`(URL 상수 묶음 `:31-38` 옆)
  2. `completeFinalLogin`(`:141-192`)을 고친다.
     - try 블록(`:151`) 앞에 `boolean passwordExpired = false;` 를 두고, try 안에서 `:152` 로 가져온 `Admin` 으로 `passwordExpired = admin.isPasswordExpired();` 를 설정한다. `getAdmin` 호출은 **try 안에 그대로 둔다**.
     - **`getAdmin` 조회가 실패하면 만료 아님으로 판정한다.** 기존 catch(`:164-166`)의 error 로그가 그대로 남고 로그인은 지금처럼 계속된다. 조회 실패가 로그인 실패로 바뀌지 않게 하기 위해서다.
     - `passwordExpired` 이면 `request.getSession().setAttribute(SESSION_PASSWORD_EXPIRED, true)` 를 하고, `:178-186` 의 saved request 와 대시보드 분기 대신 `successHandler.setDefaultTargetUrl(PASSWORD_CHANGE_URL)` 를 쓴다(이 경로는 Spring 의 리다이렉트 전략이 context-path 를 붙인다).
     - 만료가 아니면 기존 분기를 그대로 탄다.
     - 폼 로그인과 2FA 완료는 모두 이 메서드로 수렴하므로 다른 곳은 손대지 않는다.
  3. `AccessControlFilter.doFilterInternal` 을 고친다. IP 검사 try/catch 블록(`:43-56`) **뒤**, 마지막 `filterChain.doFilter`(`:58`) **앞**에 분기를 넣는다.
     - `request.getSession(false)` 에 `SESSION_PASSWORD_EXPIRED` 가 있고 요청 경로가 허용 목록 밖이면 `response.sendRedirect(request.getContextPath() + PASSWORD_CHANGE_URL)` 후 return 한다. 허용 목록 비교는 기존 패턴(`:37`)대로 `getRequestURI()` 에서 `request.getContextPath()` 길이만큼 잘라낸 경로로 한다. 현재 context-path 설정은 없으므로 동작은 같고, 설정되는 현장에서도 리다이렉트가 깨지지 않게 하기 위해서다(plan-review-2 Minor [60]). 기존 `/openapi/`·`/config/` 검사(`:37-38`)는 손대지 않는다.
     - 허용 목록(이 밖은 모두 리다이렉트):
       - `/settings`
       - 정규식 `^/api/v1/admins/\d+/password(/verify)?$` — 변경 모달
       - 정규식 `^/api/v1/admins/\d+/2fa/status$` — 화면 로드 시 배지(`settings.html:209-210`)와 2FA 모달(`config-form.html:395-396`)이 부른다. 막으면 302 를 HTML 로 따라가 `response.enabled` 가 undefined 가 되고 배지가 "비활성화"로 잘못 보인다.
       - 정규식 `^/api/v1/admins/\d+/2fa/(qrcode|enable|disable)$` — 같은 화면의 2FA 모달(`config-form.html:437`, `:469-470`, `:517-518`). 막으면 `POST` 가 302 → `GET /settings?…` 200 HTML 로 바뀌어 jQuery success 콜백이 돌고 "활성화 완료" 같은 **거짓 성공**이 뜬다. 본인/SUPER_ADMIN 검사는 컨트롤러가 이미 한다(`TwoFactorAuthRestController.java:44-56`). 2FA 설정은 비밀번호 변경을 건너뛰게 해 주지 않는다.
       - `/logout`, `/login`, `/auth/login`, `/auth/2fa` 로 시작하는 경로, `/error` 로 시작하는 경로
       - `SecurityConstants.STATIC_RESOURCES` 에 해당하는 접두(`/css/`, `/js/`, `/vendors/`, `/images/`, `/favicon.ico`)
     - **허용하지 않는 것**: `PUT /api/v1/admins/{id}`(내 정보 수정, `settings.html:183-185`). 비밀번호 변경이 아니므로 결정("변경 화면으로만 이동")에 따라 막는다. 허용 정규식은 모두 `$` 로 끝나므로 이 경로와 겹치지 않는다.
     - 이 분기는 기존 IP 검사의 catch-and-allow 블록 **밖**에 둔다. 예외 시 허용하는 정책이 강제 이동에 섞이지 않게 하기 위해서다.
     - 새 필터나 인터셉터는 만들지 않는다.
  4. `AdminRestController.updatePassword`(`:92-103`)에 `HttpServletRequest request` 파라미터를 추가한다. 변경이 성공했고 `SecurityUtil.isCurrentUser(adminId, adminService)` 이면 `request.getSession(false)` 에서 `SESSION_PASSWORD_EXPIRED` 를 제거한다. SUPER_ADMIN 이 다른 관리자의 비밀번호를 바꾼 경우에는 자기 세션을 건드리지 않는다. T2 의 동일 비밀번호 거절은 예외로 끝나므로 세션 표시가 남는다(의도).
- 참조:
  - `AuthenticationSuccessHandler.java:150-166`(try 안 조회 + catch 후 계속), `:178-189`(리다이렉트 결정)
  - `AccessControlFilter.java:36-41`(경로 건너뛰기 → `doFilter` → return 모양)
  - `SecurityUtil.java:46-57`(`getCurrentAdminId` → `getAdmin(username).getId()`), `:67-70`(`isCurrentUser`)
- 테스트: `src/test/java/com/initech/sgt/controller/PasswordExpiryFlowTest.java`(신규). 모양은 `RememberMeTest` 와 같다: `@ActiveProfiles("test") @SpringBootTest @AutoConfigureMockMvc`, `@MockitoBean AdminService`.
  - **공통 stub**(`RememberMeTest.java:50-59` 모양): `getAdminDto("admin")` 는 `LoginAdmin.builder(1L, hashed, "admin", "admin", 0, true)` 를, `getAdmin("admin")` 는 `Admin.builder().id(1L).adminName("admin").displayName("admin").password(hashed).twoFactorEnabled(false).role(AdminRole.ADMIN).passwordChangedAt(now - 91일).build()` 를 반환한다. **`.id(1L)` 은 필수다** — `SecurityUtil.getCurrentAdminId`(`:46-57`)와 `AdminRestController.hasPermissionToModify`(`:262-274`)가 `getAdmin(username).getId()` 로 본인 여부를 판정하므로, id 가 없으면 `isCurrentUser` 가 false 가 되어 `SgtException` 이 난다. `role(ADMIN)` 이므로 `isSuperAdmin` 은 false 이고 본인 판정 경로를 탄다.
  - 케이스:
    - (a) `/auth/login` POST → `redirectedUrl("/settings?passwordExpired")`
    - (b) 같은 세션으로 `GET /dashboard` → 302, `redirectedUrl("/settings?passwordExpired")`
    - (c) 같은 세션으로 `GET /settings` → 리다이렉트가 아니다. 컨트롤러가 부르는 `getAdminDto(String)`·`getAdminDto(Long)` 등은 mock 으로 채운다. 이어서 같은 세션으로 `GET /api/v1/admins/1/2fa/status` 와 `POST /api/v1/admins/1/2fa/enable`(`with(csrf())`)의 `redirectedUrl` 이 `/settings?passwordExpired` 가 **아님**을 단언한다(응답 상태는 mock 에 따라 달라지므로 리다이렉트 여부만 본다). 마지막으로 `PUT /api/v1/admins/1`(`with(csrf())`)은 `redirectedUrl("/settings?passwordExpired")` 임을 단언한다.
    - (d) 같은 세션으로 `GET /css/…` 는 리다이렉트 대상이 아니다.
    - (e) 변경 주기 이내(`passwordChangedAt = now - 1일` 로 `getAdmin("admin")` stub 을 바꿈) 계정은 `/dashboard` 로 리다이렉트된다. 회귀 확인용이다.
    - (f) 같은 세션으로 `PUT /api/v1/admins/1/password`(`with(csrf())`, JSON 본문) 성공 → 이어서 `GET /dashboard` 가 더 이상 `/settings?passwordExpired` 로 가지 않는다. `adminService.updatePassword(eq(1L), any())` 는 `.id(1L)` Admin 을 반환하도록 stub 한다. 본인 판정은 공통 stub 의 `getAdmin("admin")`(`.id(1L)`)로 통과한다 — `getAdminDto` 는 이 판정에 쓰이지 않는다.
    - (g) **remember-me 쿠키만으로는 인증되지 않음을 고정한다.** 만료 계정으로 `remember-me=on` 로그인해 쿠키를 받는다(`RememberMeTest.accessWithRememberMeCookie` `:75-96` 의 쿠키 받는 부분을 따른다). 그 다음 **세션 없이**(새 `MockHttpSession`, 또는 `.session(...)` 생략) 쿠키만 붙여 `GET /dashboard` → `status().is3xxRedirection()` + `redirectedUrlPattern("**/login")`. 이 케이스는 현재 코드에서도 통과한다. 목적은 회귀 고정이다 — 누군가 체인에 `.rememberMe(...)` 를 연결하면 이 케이스가 실패해, 그 작업이 만료 처리(성공 핸들러를 타지 않는 자동 로그인 경로)까지 함께 다루게 만든다(D2).
- 완료 조건:
  - 만료 계정은 로그인 직후 변경 화면으로 간다.
  - 변경 전에는 허용 경로 밖 모든 요청이 `contextPath + /settings?passwordExpired` 로 리다이렉트되고, `/settings` 화면이 부르는 2FA AJAX 는 리다이렉트되지 않는다.
  - 본인 변경이 성공하면 같은 세션에서 정상 이동한다.
  - remember-me 쿠키만으로는 대시보드에 들어갈 수 없다(현 동작 고정).
- 검증: `cd sgt-admin && JAVA_HOME=/opt/homebrew/opt/openjdk@21 ./gradlew test --tests 'PasswordExpiryFlowTest' --tests 'RememberMeTest' --tests 'SecurityConfigTest' --tests 'AccessLogChainIntegrationTest'` → `BUILD SUCCESSFUL in …`

### T4. (삭제 — plan-review-1)
- 원래 내용: `UserDetailsServiceImpl.java:50` 의 `credentialsNonExpired` 를 `!passwordExpired` 로 바꿔 만료 계정의 remember-me 자동 로그인을 거절.
- 삭제 이유: remember-me 자동 로그인이 체인에 연결돼 있지 않아(현재 상태 절 참조) `UserDetailsServiceImpl` 는 호출되지 않는다. 고쳐도 no-op 이고, 그 검증 케이스는 구현 여부와 관계없이 통과한다. remember-me 는 결정상 범위 밖이므로 이 PR 에서 손대지 않는다. 쿠키만으로 우회할 수 없다는 사실은 T3 케이스 (g) 로 고정한다.

### T5. 변경 화면 안내와 모달 자동 열기  (선행: T3 / 위험도: 낮음 / PR-A)
- 파일: `controller/MainController.java`, `templates/settings.html`, `templates/settings/modal/config-form.html`
- 할 일:
  - `settings(Model)`(`:102-115`)에 `HttpServletRequest` 를 받는다. `model.addAttribute("passwordExpired", 세션에 SESSION_PASSWORD_EXPIRED 존재 여부)` 를 넣는다.
  - `settings.html` 에서는 `th:if="${passwordExpired}"` 일 때만 안내 문구를 보인다. 문구(정확히 이대로): "비밀번호를 변경한 지 90일이 지났습니다. 변경 후 다른 화면을 이용할 수 있습니다."
  - `config-form.html` 의 `th:inline="javascript"` 블록(`:62`) 안, `$(document).ready`(`:64`) 앞에 `const passwordExpired = /*[[${passwordExpired}]]*/ false;` 를 두고, ready 안에서 `if (passwordExpired) $('#pwd-change-modal').modal('show');` 를 호출한다.
  - 변경 성공 뒤 이동 경로(`:183`, `/settings`)는 그대로 둔다. 세션 표시가 지워졌으므로 사용자는 이후 자유롭게 이동한다.
  - 복잡도 정규식(`:156`)은 **건드리지 않는다**.
- 참조: `MainController.java:102-115`, `config-form.html:62-72`
- 테스트: `PasswordExpiryFlowTest` 케이스 (c)의 `GET /settings` 에 다음 단언을 추가한다.
  - `model().attribute("passwordExpired", true)`
  - `content().string(containsString("비밀번호를 변경한 지 90일이 지났습니다"))` — 안내 문구가 렌더됨
  - `content().string(containsString("const passwordExpired = true"))` — 모달 자동 열기 조건이 참으로 렌더됨
  - 그리고 (e) 계열(만료 아님) 로그인 세션의 `GET /settings` 에서는 `content().string(not(containsString("비밀번호를 변경한 지 90일이 지났습니다")))` 를 단언한다.
- 완료 조건: 만료 상태로 `/settings` 에 들어오면 안내가 보이고 변경 모달이 자동으로 열린다. 만료가 아니면 안내가 없다. 2FA 배지는 실제 상태대로 표시된다.
- 검증:
  - `cd sgt-admin && JAVA_HOME=/opt/homebrew/opt/openjdk@21 ./gradlew test --tests 'PasswordExpiryFlowTest'` → `BUILD SUCCESSFUL in …`
  - 수동 확인: `./gradlew bootRun --args='--spring.profiles.active=jdbc,local'` 실행. 이미 V1/V2 가 적용된 로컬 PG 에서 V3 적용 직후 `SELECT count(*) FROM sgt_admin WHERE password_changed_at IS NULL;` → `0`(S3). 이어서 `UPDATE sgt_admin SET password_changed_at = LOCALTIMESTAMP - INTERVAL '91 days' WHERE admin_name='admin';` 를 적용한다. `localhost:8088` 에 로그인하면 `/settings?passwordExpired` 로 가고 모달이 열린다. 2FA 배지가 실제 상태로 보인다. `/dashboard` 를 직접 입력해도 되돌아온다. 모달에 현재 비밀번호와 같은 값을 새 비밀번호로 넣으면 "새 비밀번호는 현재 비밀번호와 달라야 합니다." 가 보이고 여전히 갇혀 있다.

### T6. 문서(비밀번호 변경 주기)  (선행: T3 / 위험도: 낮음 / PR-A)
- 파일: `sgt-admin/README.md`
- 할 일: "인증 및 권한" 절(`:656-666`)의 복잡도 정책 줄 아래에 다음을 한 단락으로 적는다.
  - 변경 주기 90일, 만료 시 로그인 후 `/settings` 로만 이동(같은 화면의 2FA 설정은 가능)
  - 새 비밀번호는 현재 비밀번호와 달라야 함(이전 비밀번호 이력은 보지 않음)
  - 업그레이드 시점의 기존 계정은 그 시각을 변경 시각으로 간주
  - SUPER_ADMIN 이 다른 관리자 비밀번호를 바꿔도 그 관리자의 현재 세션은 다음 로그인까지 유지
  - remember-me 에 관한 서술은 **추가하지 않는다**. 기존 `:659` "Remember-me 기능과 2FA 통합 인증" 줄도 이 PR 에서는 고치지 않는다(D2 별도 이슈에서 다룬다).
- 참조: `README.md:661`
- 테스트: 없음(문서)
- 완료 조건: README 에 위 내용이 있고, 이 PR 에서 추가한 줄에 "remember" 가 없다.
- 검증:
  - `grep -n "90일" sgt-admin/README.md` → "인증 및 권한" 절 안의 줄 번호가 1건 이상 나온다.
  - `git diff develop -- sgt-admin/README.md | grep -i '^+.*remember'` → **출력 없음**(종료 코드 1).

### T7. 세션 타임아웃 30분 명시  (선행: 없음 / 위험도: 낮음 / PR-B)
- 파일: `sgt-admin/src/main/resources/application.yml`, `sgt-admin/README.md`
- 할 일:
  - `server:` 블록(`:52-54`)에 `servlet.session.timeout: 30m` 를 추가하고, 한 줄 주석으로 이유를 적는다: "#958 점검 대응 — 기본값과 같으나 명시".
  - 프로파일 yml 에는 넣지 않는다. 그래서 `jdbc` 프로파일 함정과는 무관하다.
  - README "인증 및 권한" 절에 "유휴 세션 30분 후 만료"를 한 줄로 적는다. remember-me 는 언급하지 않는다.
- 참조: `application.yml:52-54`
- 테스트: `common/conf/SecurityConfigTest.java` 에 케이스를 하나 추가한다. `@Autowired ServerProperties` 로 `getServlet().getSession().getTimeout()` 이 `Duration.ofMinutes(30)` 인지 확인한다. 기본값과 같아서 회귀를 막는 고정 테스트일 뿐이다.
- 완료 조건: 설정 파일에 30분이 명시되고 바인딩된다. 동작 변화는 없다.
- 검증:
  - `cd sgt-admin && JAVA_HOME=/opt/homebrew/opt/openjdk@21 ./gradlew test --tests 'SecurityConfigTest'` → `BUILD SUCCESSFUL in …`
  - `git diff develop -- sgt-admin/README.md | grep -i '^+.*remember'` → 출력 없음.

### T8. multipart 상한 축소(100MB / 500MB) — 실서버 테스트로 S1 먼저  (선행: 없음(D1 확정됨) / 위험도: **보통**(고객 업로드 회귀) / PR-B)
- 파일: `sgt-admin/src/main/resources/application.yml`, `sgt-admin/README.md`, `src/test/java/com/initech/sgt/rest/ResourceUploadLimitRealServerTest.java`(신규)
- 할 일:
  1. **S1 을 실서버 테스트로 먼저 한다**(값을 바꾸기 전 현재 코드로).
     - `ResourceUploadLimitRealServerTest` 를 만든다. 모양은 `ConfigServerSecurityRealServerTest` 와 같다: `@SpringBootTest(webEnvironment = RANDOM_PORT) @ActiveProfiles("test") @AutoConfigureTestRestTemplate`, 리다이렉트를 따라가지 않는 `TestRestTemplate`.
     - 상한은 테스트 속성으로 작게 둔다: `@SpringBootTest(properties = {"spring.servlet.multipart.max-file-size=1KB", "spring.servlet.multipart.max-request-size=4KB", "resources.batch-path=${java.io.tmpdir}/sgt-958-batch"})`. 실제 운영 값(100MB/500MB)과 무관하게 "상한을 넘으면 어떻게 되는가"를 재현하는 테스트다. `resources.batch-path` 를 임시 디렉터리로 돌리는 이유는 `/batch` 성공 케이스가 업로드 파일을 그 경로에 저장하기 때문이다(`ResourceRestController.java:107-114`).
     - `@MockitoBean AdminService`(로그인용, `RememberMeTest` 와 같은 stub), `@MockitoBean ResourceService`(`addResources` 가 빈 Set 반환), `@MockitoBean ResourceBatchService`(`handleBatchFile` 은 아무것도 하지 않음)를 둔다.
     - 로그인 절차: `GET /login` → 응답의 `JSESSIONID` 쿠키와 HTML 의 `_csrf` hidden 값(`login.html:22-23`)을 뽑는다 → `POST /auth/login`(form: `id`, `password`, `_csrf`) → 새 `JSESSIONID`(세션 고정 방어로 id 가 바뀐다) → 새 세션으로 다시 `GET /login` 해서 로그인 뒤 CSRF 토큰을 얻는다(`HttpSessionCsrfTokenRepository` 는 로그인 때 토큰을 바꾼다).
     - **CSRF 는 헤더로 보낸다.** 업로드 요청마다 `X-CSRF-TOKEN: <토큰>` 헤더를 붙인다. 이는 `HttpSessionCsrfTokenRepository`(`SecurityConfig.java:273`)의 기본 헤더명이고, 브라우저가 `fragments/config.html:154-158` 에서 `_csrf_header` meta 값으로 보내는 것과 같은 경로다. **multipart 본문에 `_csrf` 파트를 넣지 않는다** — 파트로 보내면 `CsrfFilter` 가 보안 필터 안에서 multipart 를 파싱해 브라우저와 다른 응답을 S1 결과로 고정하게 된다(plan-review-2 Minor [60]).
     - 케이스:
       - (a) `POST /api/v1/resources`, `POST /api/v1/resources/batch`, `PUT /api/v1/resources/1` 에 2KB 파일 → 상한 초과 응답.
       - (b) `POST /api/v1/resources/bulk` 에 1KB 미만 파일 5개(합계 4KB 초과) → 상한 초과 응답.
       - (c) `POST /api/v1/resources/bulk` 에 512B 파일 1개 → 200, `resourceService.addResources` 호출됨.
       - (d) **`POST /api/v1/resources/batch` 에 상한 이하 xlsx**(파트 이름 `file`, 파일명 `resource_batch.xlsx`, content-type `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`, 512B 바이트) → 200, `resourceBatchService.handleBatchFile(any(File.class), eq("resource_batch.xlsx"))` 호출됨. 이슈 수용 기준 "리소스 배치 xlsx 업로드 정상 동작(축소된 상한 내)"에 대응한다. 서비스는 mock 이므로 바이트가 실제 xlsx 일 필요는 없다.
     - **첫 실행 결과(상태 코드, 본문, 연결 리셋 여부)를 기록하고, 그 값을 (a)(b) 의 기대 상태로 고정한다.** 결과는 PR 본문에도 적는다. 400 이 아니더라도 이 이슈에서 예외 처리 구조는 바꾸지 않는다(S1).
     - 연결 리셋으로 응답 자체를 못 받으면 (a)(b) 는 "예외 발생 또는 4xx" 로 단언하고, 그 사실을 PR 본문에 적는다.
  2. `application.yml:24-27` 의 두 값을 `max-file-size: 100MB`, `max-request-size: 500MB` 로 바꾼다(D1 확정). 한 줄 주석으로 근거(#958)와 오버라이드 방법(`admin.env.SPRING_SERVLET_MULTIPART_MAX_FILE_SIZE` / `…_MAX_REQUEST_SIZE`)을 적는다.
  3. **helm 에 새 knob 을 만들지 않는다**. `admin.env` 패스스루(`helm/templates/admin.yaml:140`)로 충분하다.
  4. README 에 상한(단건 100MB, 요청 합계 500MB)과 오버라이드 방법, 업그레이드 주의를 적는다. 업그레이드 주의는 "이전 상한 1GB 기준으로 100MB 보다 큰 파일을 쓰던 현장은 업그레이드 전에 `admin.env.SPRING_SERVLET_MULTIPART_MAX_FILE_SIZE`(필요하면 `…_MAX_REQUEST_SIZE`) 로 올릴 것"이다.
- 참조: `common/conf/ConfigServerSecurityRealServerTest.java:23-33`(실서버 테스트 모양), `controller/RememberMeTest.java:49-59`(로그인 stub), `application.yml:24-27`, `RestControllerExceptionHandler.java:92-100`(메시지가 `max-file-size` 를 그대로 보여 준다), `fragments/config.html:154-158`(CSRF 헤더 경로)
- 테스트:
  - `ResourceUploadLimitRealServerTest`(위 (a)~(d)). 상한 강제 동작의 자동 회귀가 된다.
  - `SecurityConfigTest` 에 `@Autowired MultipartProperties` 로 `getMaxFileSize()` = `DataSize.ofMegabytes(100)`, `getMaxRequestSize()` = `DataSize.ofMegabytes(500)` 를 고정하는 케이스를 추가한다.
- 완료 조건:
  - `max-file-size` 를 넘는 업로드는 4경로 모두 S1 에서 확인한 응답으로 거부되고 서비스가 호출되지 않는다.
  - `/bulk` 의 합계가 `max-request-size` 를 넘으면 거부된다.
  - 상한 이하 업로드는 성공한다(`/bulk` 512B, `/batch` xlsx).
  - yml 기본값이 `max-file-size: 100MB`, `max-request-size: 500MB` 다.
- 검증: `cd sgt-admin && JAVA_HOME=/opt/homebrew/opt/openjdk@21 ./gradlew test --tests 'ResourceUploadLimitRealServerTest' --tests 'SecurityConfigTest'` → `BUILD SUCCESSFUL in …`

### 마지막. 전체 회귀  (선행: 각 PR 의 모든 태스크)
- 검증: `cd sgt-admin && JAVA_HOME=/opt/homebrew/opt/openjdk@21 ./gradlew test` → `BUILD SUCCESSFUL in …`. 실패 시 `N tests completed, M failed` 가 나온다. PR-A·PR-B 각각에서 실행한다.

## 완료 조건 (전체)

PR-A(T1~T6)
- [ ] 비밀번호 변경 주기 90일을 넘긴 계정은 로그인 직후 `/settings?passwordExpired`(변경 모달 자동 열림, 안내 문구)로만 이동하고, 허용 경로 밖 요청은 그리로 리다이렉트된다. `/settings` 의 2FA AJAX 는 정상 동작한다 ↔ `PasswordExpiryFlowTest` (a)(b)(c)(d)
- [ ] 비밀번호 변경 직후 `password_changed_at` 이 그 시각으로 기록되고, 같은 세션에서 다른 화면으로 이동할 수 있다 ↔ `AdminServiceTest`(T2 (a)), `PasswordExpiryFlowTest` (f)
- [ ] 현재 비밀번호와 같은 값으로는 변경할 수 없다(400, 비밀번호·변경 시각 불변) ↔ `AdminServiceTest`(T2 (b))
- [ ] remember-me 쿠키만으로는 강제 변경을 건너뛸 수 없다(현 동작 고정) ↔ `PasswordExpiryFlowTest` (g)
- [ ] V3 적용 전 행(컬럼이 없던 계정)과, 복잡도 정책 이전에 만든 약한 비밀번호 계정이 업그레이드 직후 정상 로그인된다(강제 변경 없음). V3 가 기존 행을 업그레이드 시각으로 채우고, 판정은 BCrypt 재검증 없이 시각만 본다 ↔ `check-admin-schema.sh`(V3 가 PG 에 적용됨) + `PasswordExpiryFlowTest` (e) + T5 수동 확인(V1/V2 가 적용된 로컬 PG 에서 V3 적용 직후 NULL 0건)
- [ ] 회귀: 기존 V1·V2 무변경 ↔ `check-admin-schema.sh` ①
- [ ] 회귀: 만료 아닌 계정의 폼 로그인·2FA·remember-me 쿠키 발급·saved request 리다이렉트가 그대로다 ↔ `RememberMeTest`, `SecurityConfigTest`, 전체 `./gradlew test`
- [ ] 회귀: 복잡도 규칙(서버 상수와 화면 JS 2곳)이 무변경이다 ↔ `git diff develop -- sgt-admin/src/main/resources/templates/admin/add.html` 결과가 비어 있고, `config-form.html` 의 `passwordPattern` 줄이 그대로다
- [ ] README 에 remember-me 서술을 추가하지 않았다 ↔ `git diff develop -- sgt-admin/README.md | grep -i '^+.*remember'` 출력 없음

PR-B(T7~T8)
- [ ] 세션 타임아웃 설정이 `server.servlet.session.timeout: 30m` 로 명시되고 바인딩된다 ↔ `SecurityConfigTest`(T7)
- [ ] `max-file-size`=100MB 를 넘는 업로드는 `/api/v1/resources`·`/batch`·`/bulk`·`PUT /{resourceId}` 에서 **500 + `errorCode` 9999**(S1 실측 2026-11-08: `MaxUploadSizeExceededException` 이 핸들러 선택 전에 나서 `basePackages` 한정 advice 를 건너뛰고 `GlobalExceptionHandler` 의 일반 예외 처리로 떨어짐 — 구조 변경은 후속 이슈)로 거부되고, `/bulk` 합계가 `max-request-size`=500MB 를 넘어도 거부된다 ↔ `ResourceUploadLimitRealServerTest` (a)(b) + `SecurityConfigTest`
- [ ] 상한 이하의 리소스 배치 xlsx 업로드와 `/bulk` 업로드는 정상 동작한다 ↔ `ResourceUploadLimitRealServerTest` (c)(d)
- [ ] PR-B 머지 후 이슈 #958 close

## 리스크 · Spikes · 롤백

**리스크**
- **[롤백 주의] V3 는 되돌릴 수 없다.** additive(nullable + DEFAULT)라 구 admin 이미지도 이 스키마에서 동작한다. 다만 V3 를 수정하거나 지우는 것은 출시 뒤 금지다. 고칠 게 생기면 V4 로 한다.
- **[롤백 주의] 구 이미지로 롤백할 때**: 구 admin 의 Flyway 가 DB 에 적용된 "로컬에 없는 V3" 를 어떻게 다루는지 확인하지 않았다(S2).
- **업그레이드 직후 강제가 없다**: 결정대로 기존 계정은 업그레이드 시각부터 90일을 센다. 그래서 점검 직후 바로 효과가 보이지 않는다. 릴리즈 노트에 적는다.
  - 공개된 시드 기본 비밀번호(`V2__seed.sql:3`)를 아직 쓰는 현장도 90일 동안은 강제되지 않는다. 이 점은 결정 범위 밖이라 그대로 둔다.
- **동일 비밀번호 거절은 직전 값만 본다**: A→B→A 처럼 번갈아 쓰면 막지 못한다. 이력 관리는 범위 밖이다.
- **세션 표시 방식의 한계**:
  - 로그인 중에 90일 경계를 넘긴 세션은 다음 로그인 전까지 강제되지 않는다. 유휴 30분 + `maximumSessions(1)` 로 범위는 작다.
  - SUPER_ADMIN 이 다른 관리자의 비밀번호를 바꿔도 그 관리자의 현재 세션 표시는 다음 로그인 때 사라진다.
  - shortcut: 세션 표시는 파드 메모리 세션에 있어 admin replicaCount=1 을 전제한다. 이는 `AdminService.expireSessions` 의 기존 전제와 같다.
- **`AccessControlFilter` 이중 등록**: `@Component` `OncePerRequestFilter` 라 서블릿 레벨에도 등록되지만, bean 이름이 같아 두 번째 실행은 건너뛴다. 분기 자체도 멱등이다.
- **AJAX 요청도 302 로 바뀐다**: 대상 화면 자체가 `/api/v1/admins/{id}/2fa/status` 를 부르므로(그리고 2FA 모달이 qrcode/enable/disable 을 부르므로) 이 경로들은 허용 목록에 넣었다. 허용 밖에 남는 `PUT /api/v1/admins/{id}`(내 정보 수정)는 302 를 받는다. 브라우저는 302 에서 POST 가 아닌 메서드를 유지하므로 `PUT /settings?passwordExpired` 가 되고, `/settings` 는 GET 전용(`MainController.java:102`)이라 오류 응답 → 화면은 error 콜백("수정에 실패하였습니다.", `settings.html:191-193`)을 보일 것으로 예상한다. 실측하지 않았다. 거짓 성공이 아니므로 받아들인다.
- **업로드 상한 축소(1GB/10GB → 100MB/500MB)는 고객에게 보이는 회귀다**: 100MB 보다 큰 리소스 파일을 배포하던 현장은 업그레이드 뒤 업로드가 거부된다. 우리는 그 사실을 볼 수 없다. README·릴리즈 노트에 env 오버라이드 방법을 함께 적는다.
- (기존 결함, 이번 변경과 무관, plan-review-2 Minor [65]) `AuthenticationSuccessHandler` 는 싱글턴이 공유하는 `successHandler` 의 `setDefaultTargetUrl` 을 요청마다 바꾼다(`:182`, `:185`, `:188`). 동시 로그인 시 목적지가 섞일 수 있다. 만료 분기도 같은 방식을 쓰지만, 세션 표시와 필터가 최종 목적지를 다시 강제하므로 보안 영향은 없다. 이 PR 에서 고치지 않는다.

**Spikes / Unknowns**
- **S1 (T8 선행, T8 의 실서버 테스트 첫 실행으로 해소)**: 상한 초과 시 실제 응답이 무엇인지 확인한다. triage 는 `RestControllerExceptionHandler` 의 400 `NOT_VALID_PARAMETER` 를 가정했다.
  - 그런데 multipart 파싱은 `DispatcherServlet` 이 핸들러를 고르기 **전**에 일어날 수 있다. 그래서 `basePackages` 로 한정된 advice 가 적용되지 않고 다른 경로(413, 500, `/error` 포워드)로 갈 수 있다. CSRF 를 헤더로 보내므로(T8) 보안 필터 안의 파싱은 브라우저와 같은 조건이다.
  - 초과량이 크면 Tomcat 이 연결을 끊을 수도 있다.
  - MockMvc 는 multipart 크기를 강제하지 않으므로 반드시 `RANDOM_PORT` 실서버로 확인한다.
  - 400 이 아니더라도 이 이슈에서 예외 처리 구조를 바꾸지 않는다. 결과만 테스트로 고정·문서화하고, 필요하면 후속 이슈로 올린다.
- **S2**: 구 admin 이미지로 롤백할 때 Flyway 가 "적용됐지만 로컬에 없는 V3" 에서 기동을 거부하는지 확인한다. 이 세션에서는 Boot 가 관리하는 Flyway 버전과 기본 `ignore-migration-patterns` 를 확인하지 않았다. 확인 방법: V3 를 적용한 로컬 PG 에 `v3.10.0` admin jar 를 띄워 본다. 거부한다면 롤백 절차(helm/README 업그레이드 절)에 주의를 추가한다.
- **S3**: `ADD COLUMN … DEFAULT LOCALTIMESTAMP` 가 기존 행을 ALTER 시점 값으로 채우는지 확인한다. PostgreSQL 의 문서화된 동작이지만 이 세션에서 실측하지 않았다. `check-admin-schema.sh` 는 종료 시 컨테이너를 지우므로 여기서는 확인할 수 없다. **T5 수동 확인(V1/V2 를 이미 적용한 로컬 PG)에서만** `SELECT count(*) FROM sgt_admin WHERE password_changed_at IS NULL` = 0 을 확인한다.
- **S4(작음)**: Boot 4.1.2 에서 `ServerProperties`·`MultipartProperties` 빈의 패키지 위치(T7/T8 고정 테스트의 import). 이 세션에서 확인하지 않았다. 구현 시 IDE/컴파일로 찾으면 되고 계획에는 영향이 없다.

## 결정 포인트

모두 확정되었다. 남은 사용자 판단은 없다.

- **D1. multipart 상한 값 — 확정(2026-11-08)**: `max-file-size: 100MB`, `max-request-size: 500MB`.
  - 근거 1: 현재 1GB/10GB 는 실제로 받을 수 있는 용량과도 맞지 않는다. 리소스 PVC 기본은 5Gi 이고, `/tmp` emptyDir 에 sizeLimit 이 없어 노드 디스크를 쓴다.
  - 근거 2: 대상 4경로는 관리자가 올리는 리소스 파일과 템플릿 xlsx 다. 100MB 는 문서·xlsx 에 충분히 넉넉하다.
  - 근거 3: `/bulk` 는 파일 여러 개를 한 요청에 담으므로 합계 상한을 단건의 5배로 둔다.
  - 근거 4: 더 큰 파일이 필요한 현장은 새 knob 없이 `admin.env.SPRING_SERVLET_MULTIPART_MAX_FILE_SIZE` / `…_MAX_REQUEST_SIZE` 로 올린다.
- **D2. remember-me 자동 로그인 미연결은 별도 이슈로 — 확정(2026-11-08): 권장값 채택.** 이 PR 에서는 손대지 않는다. **별도 이슈 생성은 나중에(사용자)** 한다. 제목 안: `fix(admin): remember-me 쿠키를 발급하지만 자동 로그인 필터가 체인에 없다`.
  - 사실: 체인에 `.rememberMe(...)` 가 없어 쿠키는 발급되지만 자동 로그인은 되지 않는다. README `:15`, `:659` 의 "Remember-Me 통합" 서술과 다르다.
  - 그 이슈에서 다룰 것: 연결할지/쿠키 발급을 없앨지 결정, 연결한다면 `UserDetailsServiceImpl.java:50` 의 `credentialsNonExpired` 를 `!passwordExpired` 로(옛 T4), T3 케이스 (g) 갱신, README 서술 정정.
  - 이슈 생성은 이 계획의 실행 범위가 아니다.
- **D3. 90일을 코드 상수로 — 확정(2026-11-08): 권장값 채택.** `Admin.PASSWORD_MAX_AGE`.
  - 복잡도 규칙도 코드 상수(`AdminService.PASSWORD_POLICY`)라 같은 방식이다.
  - 보안정책 테이블로 옮기면 `PolicyType` 확장이 따라오고, 롤링 업데이트 중 구 파드의 enum 변환 실패 위험이 생긴다(triage). 현장별 주기 요구가 생기면 별도 이슈로 다룬다.
- **D4. 강제 변경 화면 — 확정(2026-11-08): 권장값 채택.** 새 페이지 없이 기존 `/settings` 와 비밀번호 변경 모달을 재사용하고, 안내 문구를 붙여 자동으로 연다. 같은 화면의 2FA 설정은 허용하고, 내 정보 수정은 막는다(T3 허용 목록).

## 자가 점검
- [x] 모든 경로가 세션 내 Read/Grep 결과다. 신규 파일 5개(V3, 테스트 3, 계획서)는 신규로 표시했다. 이번 갱신에서 `BCryptUtil.java:36`, `AdminService.java:308-316`/`:473-478`, `SecurityUtil.java:46-89`, `AdminRestController.java:262-274`, `SgtException.java:16,32`, `RestControllerExceptionHandler.java:109-117`, `fragments/config.html:149-158`, `layouts/layout.html:5`, `SecurityConfig.java:273`, `ResourceRestController.java:58-59,99-121`, `application-test.yml:67`, `AdminServiceTest.java:37-38,82-105` 를 다시 확인했다.
- [x] 모든 태스크에 참조 구현과 검증 명령이 있다. T6 는 문서라 테스트가 없고 grep/diff 로 검증한다. T4 는 삭제했다.
- [x] 실행자가 아키텍처 결정을 하게 만드는 태스크가 없다. 끼울 위치(성공 핸들러, 기존 `AccessControlFilter`, `updatePassword` 의 `:312`~`:314` 사이)와 허용 경로 목록, `getAdmin` 실패 시 판정 규칙, CSRF 전송 방식, 안내 문구와 JS 변수명을 지정했다. D1~D4 는 모두 확정이다. T8 의 거부 상태(S1 실측 결과 500 + 9999 로 확정)만 S1 실측으로 정하되, 예외 처리 구조는 바꾸지 않는다고 못박았다.
- [x] 가장 위험한 태스크(T1 V3 마이그레이션)를 맨 앞에 두었다. T8 은 S1(실서버 테스트 첫 실행)을 값 변경보다 앞에 두었다.
