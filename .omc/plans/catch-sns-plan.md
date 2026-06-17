# Catch SNS — 수집 기반 소셜 앱 확장 작업 계획

> 로컬 전용 "사물 누끼 스티커 수집 앱"을, **잡은 사물들을 공유·팔로우·발견하는 소셜 네트워크**로 확장.
> 가입(Apple 로그인)해야 사용 가능. 프로필 = 내 수집 항아리 + 팔로워/팔로잉. 팔로잉 피드. 폴더. 광고+코스메틱 수익.

---

## 1. Requirements Summary

### 확정 결정 (사용자)
| 항목 | 결정 |
|------|------|
| 인증 | **Sign in with Apple** → Supabase Auth. **가입 필수**(게스트 사용 불가). Supabase CLI로 스키마 관리 |
| 프로필 | 수집(catches) + 팔로워 + 팔로잉. 프로필 비주얼 = 기존 **물리 항아리**(SpriteKit) 유지 |
| 공개범위 | **기본 전체 공개**. 개별 캐치·폴더 단위로 비공개 전환 가능 |
| 홈 피드 | **팔로잉 피드만** (내가 팔로우한 사람들의 최신 수집). 발견은 검색/프로필 경유 |
| 폴더 | **내 수집 정리용**(주제별). 폴더별 공개/비공개 |
| 수익 | **AdMob 광고 + 코스메틱 IAP(StoreKit 2)**. 구독 없음 |
| 기존 자산 | 카메라·Vision 누끼·스캔 연출·물리 씬은 그대로 재사용. 로컬 `StickerStore`를 클라우드 동기화로 대체 |

### 핵심 흐름
1. 첫 실행 → Apple 로그인 → 사용자명(@handle) 설정(온보딩).
2. 카메라 → 누끼 → **Catch** → 클라우드 업로드(Storage) + `catches` 레코드 생성 → 내 항아리에 합류.
3. 내 프로필: 물리 항아리(내 수집) + 수집수/팔로워/팔로잉, 폴더 탭.
4. 홈: 팔로잉한 사람들의 최신 캐치 피드(좋아요/탭→상대 항아리).
5. 검색으로 사용자 찾기 → 팔로우.
6. 광고(피드 네이티브) + 코스메틱(항아리 스킨/물리 이펙트) 구매.

---

## 2. 아키텍처

```
[iOS 앱 (SwiftUI)]
  ├─ 기존: Camera / Vision 누끼 / ScanReveal / SpriteKit 물리 항아리
  ├─ 신규: supabase-swift SDK
  │    ├─ Auth (Sign in with Apple)
  │    ├─ Postgres (profiles, catches, follows, folders, likes, reports, blocks, entitlements)
  │    └─ Storage (sticker 이미지 버킷, 비공개 + 정책/서명 URL)
  ├─ StoreKit 2 (코스메틱 비소모성 IAP)
  └─ Google Mobile Ads + ATT/UMP 동의

[Supabase 백엔드]
  ├─ DB 마이그레이션 (supabase/migrations/*.sql, CLI 관리)
  ├─ RLS 정책 (가시성 강제: 공개 OR 소유자 OR(추후) 팔로워)
  ├─ Storage 버킷 정책
  └─ Edge Functions (필요 시: 서명 URL 발급, 신고 처리, 피드 RPC)
```

### 프로젝트 구조 (신규/변경)
```
Catch/
├─ Services/
│  ├─ SupabaseManager.swift      # 클라이언트 싱글톤(URL/anon key)
│  ├─ AuthService.swift          # Apple 로그인, 세션, 로그아웃, 탈퇴
│  ├─ CatchRepository.swift      # 캐치 업로드/조회/삭제 (구 StickerStore 대체)
│  ├─ ProfileRepository.swift    # 프로필/팔로우/검색
│  ├─ FolderRepository.swift     # 폴더 CRUD/배정
│  ├─ FeedRepository.swift       # 팔로잉 피드 페이지네이션
│  ├─ EntitlementStore.swift     # StoreKit 구매/소유 동기화
│  └─ AdsService.swift           # AdMob + ATT/UMP
├─ Models/  (Catch, Profile, Folder, FeedItem, Cosmetic …)
├─ Views/
│  ├─ Auth/  (SignInView, OnboardingUsernameView)
│  ├─ Feed/  (FeedView, FeedCardView)
│  ├─ Profile/ (ProfileView=항아리+카운트, FollowListView, EditProfileView)
│  ├─ Search/ (UserSearchView)
│  ├─ Folder/ (FolderListView, FolderDetailView, FolderPickerView)
│  ├─ Store/ (CosmeticStoreView)
│  └─ (기존 Camera/ScanReveal/Home 재사용·재배치)
└─ App/ (RootView: 세션 분기 — 미로그인→Sign in, 로그인→TabView)
supabase/
├─ config.toml
└─ migrations/  (0001_init.sql, 0002_rls.sql, …)
```

### 데이터 모델 (Postgres)
```sql
-- profiles: auth.users 1:1. 생성은 auth.users insert 트리거(handle_new_user)로 보장(클라 upsert 갭 제거)
profiles(id uuid PK refs auth.users, username citext UNIQUE
           CHECK (username ~ '^[a-z0-9_]{3,20}$'),           -- 길이·문자셋 강제
         display_name text, avatar_url text, bio text,
         username_changed_at timestamptz null,                -- 변경 쿨다운(예: 30일)
         created_at timestamptz default now(), updated_at timestamptz default now())
  -- 예약어(admin, catch, support, official …)는 시드 테이블/트리거로 거부

folders(id uuid PK, owner_id uuid refs profiles, name text, is_public bool default true,
        sort int default 0, created_at timestamptz default now(), updated_at timestamptz default now())

catches(id uuid PK, owner_id uuid refs profiles, folder_id uuid null refs folders,
        image_path text, body_path text, width int, height int,
        title text null, is_public bool default true,
        like_count int default 0,                             -- 트리거로만 갱신(클라 UPDATE는 RLS로 차단)
        caught_at timestamptz default now(), updated_at timestamptz default now())
  index (owner_id, is_public, caught_at desc);  index (folder_id)

follows(follower_id, followee_id, created_at, PK(follower_id, followee_id))
likes(user_id, catch_id refs catches, created_at, PK(user_id, catch_id))   -- INSERT/DELETE가 like_count 트리거 발동
blocks(blocker_id, blocked_id, created_at, PK(blocker_id, blocked_id))
reports(id uuid PK, reporter_id, target_type, target_id, reason, created_at)
entitlements(user_id, product_id, acquired_at, PK(user_id, product_id))     -- 서버 영수증 검증 후 기록
```
카운트(팔로워/팔로잉/수집수)는 초기엔 `count(*)`, 부하 시 트리거 denormalized 전환. `like_count`는 처음부터 `likes` 트리거로 관리(클라이언트 직접 UPDATE 금지).

### 2.5 보안·가시성 모델 (RLS) — Phase 0에 먼저 구축
모든 가시성은 **DB RLS로 강제**한다(클라이언트 필터에 의존 금지 — anon key로 REST 직접 호출 가능하므로).

**캐치 가시성 정의(단일 규칙)**:
```
catch가 보이려면 = 소유자 본인
                 OR ( is_public
                      AND (folder_id IS NULL OR (SELECT is_public FROM folders f WHERE f.id = folder_id))
                      AND NOT EXISTS(blocks where (소유자↔요청자 어느 방향이든 차단)) )
```
- **폴더/캐치 합성**: 캐치가 공개여도 **비공개 폴더에 속하면 숨김**. RLS는 folders와 JOIN해 판정.
- **차단 양방향 배제**: catches/profiles/follows/feed RLS 전부에 `NOT EXISTS(blocks …)` 포함(직접 id 조회로도 우회 불가).
- **like_count 쓰기**: catches에 대한 클라이언트 UPDATE는 RLS로 거부, 트리거만 갱신.

### Storage & 서명 URL
- 버킷 `stickers` **비공개**. 경로 `catches/{owner_id}/{catch_id}.png`, body `.../{catch_id}_body.png`.
- 이미지 접근은 **위 캐치 가시성 RLS를 통과한 행에 한해** 단기 **서명 URL**(TTL 5~15분) 발급.
- ⚠️ **서명 URL은 발급 후 TTL 동안 유효**(즉시 무효화 불가) → 비공개 전환 직후 최대 TTL만큼 잔존 가능. 민감 즉시성이 필요하면 **프록시 엔드포인트(Edge Function에서 매 요청 RLS 재검사 후 스트림)**로 대체. 기본은 짧은 TTL + 이 한계를 문서화.
- **EXIF/위치 제거**: 업로드 전 메타데이터(특히 GPS) **명시적 제거**(렌더 재인코딩). 현재 누끼 파이프라인이 우연히 제거하지만 의존 금지 — 별도 단계+검증.

---

## 3. 단계별 로드맵 (각 단계 독립 출시 가능)

### Phase 0 — 백엔드 부트스트랩 & Apple 인증 & RLS
- `supabase init` → `config.toml`, `0001_init.sql`(스키마), `0002_rls.sql`(정책), `0003_triggers.sql`(handle_new_user, like_count, updated_at).
- Supabase 프로젝트 생성, **Apple provider** 설정(Services ID, Key, Team ID).
- Xcode: **Sign in with Apple capability** + `supabase-swift` SPM.
- `AuthService`: Apple 로그인 → 세션 영속/복원/로그아웃.
- `RootView`: 세션 없으면 `SignInView`, 있으면 메인 TabView.
- 온보딩: 최초 로그인 시 `username` 설정 — **정규식 `^[a-z0-9_]{3,20}$` + 예약어 거부 + citech UNIQUE**. `profiles`는 `handle_new_user` 트리거로 자동 생성.
- **RLS 전부 이 단계에 구축**: §2.5 캐치 가시성(폴더 합성 포함), 차단 양방향 배제, like_count 클라 UPDATE 차단.
- **AC0**:
  - [ ] `supabase db reset`로 모든 테이블·RLS·트리거·인덱스 생성.
  - [ ] Apple 로그인 시 트리거로 `profiles` 자동 생성, 재실행 시 세션 복원.
  - [ ] 미로그인 시 모든 기능 진입 불가(가입 강제).
  - [ ] username 정규식 위반·예약어·중복 거부, 유효값 저장 후 진입.
  - [ ] **RLS 매트릭스 테스트**: anon key 직접 REST 호출로도 비공개/차단 캐치 조회 불가.

### Phase 1 — 클라우드 캐치 + 안전 최소선 (★ 공개 UGC 출시 게이트)
> Apple Guideline 1.2: 공개 UGC 앱은 **신고·차단·콘텐츠 필터**가 없으면 심사 통과 불가.
> 기본 전체 공개가 이 단계에서 시작되므로 **모더레이션 최소선을 같은 단계에 포함**(Critic CRITICAL 반영).
- `CatchRepository.upload(image:)`: 누끼 PNG(트림·1024)+body(256) → **EXIF/GPS 명시 제거 후** Storage 업로드 → `catches` insert.
- 프로필 항아리: 내 `catches`를 서버 로드해 `StickerScene`에 투하(기존 로직 재사용, 소스만 교체).
- 로컬 캐시(오프라인) + 업로드 실패 재시도 큐(멱등 업서트). 기존 로컬 `StickerStore` 대체.
- **로컬→클라우드 1회 마이그레이션**(기존 manifest 캐치 업로드, 멱등·실패 복구).
- **안전 최소선**: 캐치/유저 **신고**(`reports`) + **차단**(`blocks`) UI + 업로드 시 **민감콘텐츠 점검**(iOS 17+ `SensitiveContentAnalysis` 가능 시 차단/경고, 불가 환경은 사후 신고).
- **AC1**:
  - [ ] Catch 시 이미지 2종 업로드 + `catches` 생성(소유자=uid), **업로드물에 GPS/EXIF 없음(검증)**.
  - [ ] 타 기기 동일 계정 로그인 시 수집 동기화 로드.
  - [ ] 비공개 캐치는 RLS상 타인 조회 불가(쿼리·스토리지 모두, anon 직접호출 포함).
  - [ ] 오프라인 Catch 후 복귀 시 자동·중복없이 업로드.
  - [ ] **신고·차단 동작**, 차단 즉시 상호 비노출. (출시 게이트)

### Phase 2 — 소셜 그래프 (프로필·팔로우·검색)
- `ProfileView`: 물리 항아리(해당 유저의 공개 수집) + 수집수/팔로워/팔로잉 카운트 + 팔로우 버튼.
- `follows` 기반 follow/unfollow(낙관적 업데이트), `FollowListView`(팔로워/팔로잉 목록).
- `UserSearchView`: username 부분검색(citext, trigram 인덱스).
- 본인 프로필 편집(display_name, bio, avatar).
- **AC2**:
  - [ ] 타 유저 프로필에서 공개 수집만 항아리에 보이고 카운트 3종 정확.
  - [ ] 팔로우/언팔로우가 즉시 반영되고 카운트 갱신, 재진입 후 유지.
  - [ ] username 검색이 부분일치로 결과 반환(대소문자 무시).
  - [ ] 차단한 유저는 검색·프로필·피드에서 상호 비노출.

### Phase 3 — 팔로잉 피드
- `FeedRepository.page(after:)`: 내가 팔로우한 유저들의 가시 캐치를 **커서 기반**(`(caught_at, id)` 키셋) 페이지네이션 — offset은 시간순 피드에서 중복/누락 유발하므로 금지.
- `FeedView`: 캐치 카드(이미지 + @username + 시간 + 좋아요), 무한 스크롤, 풀-투-리프레시.
- 좋아요(`likes`) 토글 + 카운트.
- 빈 피드 온보딩: 팔로우 0명일 때 추천 유저/검색 유도(발견 경로).
- **AC3**:
  - [ ] 팔로우한 유저의 새 캐치가 피드 상단에 시간순으로 표시.
  - [ ] 비팔로우 유저 캐치는 피드에 안 나옴. 비공개 캐치도 안 나옴.
  - [ ] 좋아요 토글이 즉시 반영되고 새로고침 후 유지.
  - [ ] 20개 단위 페이지네이션, 스크롤 끝에서 다음 페이지 로드.

### Phase 4 — 폴더 (내 수집 정리)
- `FolderRepository`: 생성/이름변경/삭제/정렬, 폴더별 `is_public`.
- 캐치를 폴더에 배정(`FolderPickerView`), 미배정=기본 항아리.
- `FolderDetailView`: 해당 폴더 수집을 별도 항아리로 표시.
- **AC4**:
  - [ ] 폴더 생성 후 캐치 배정 시 해당 폴더 항아리에 표시, 미배정 캐치는 전체 항아리에.
  - [ ] 폴더 비공개로 두면 그 안 캐치는 타인 프로필·피드에서 숨김.
  - [ ] 폴더 삭제 시 내부 캐치는 미배정으로 이동(삭제 안 됨).

### Phase 5 — 고급 모더레이션 & 계정 삭제 & 데이터 권리
> 신고·차단·콘텐츠필터 최소선은 Phase 1에 이미 포함. 여기선 운영·법적 완성도.
- **모더레이션 큐**: 신고 누적 시 자동 숨김/검수 플래그, 운영자 처리 경로(서버).
- **계정 삭제(App Store 필수)**: 프로필·캐치·Storage 전량 삭제. Storage 객체가 수백 개일 수 있어 **비동기 작업(Edge Function/큐)**으로 처리, 즉시 동기 삭제 타임아웃 방지.
- **GDPR**: 삭제뿐 아니라 **데이터 내보내기(export)** 제공.
- **rate limiting**: 팔로우·좋아요·신고·업로드·API에 유저별 제한(악용·스팸 방지).
- ToS/개인정보 처리방침, EULA(부적절 콘텐츠 무관용).
- **AC5**:
  - [ ] 신고 임계 도달 시 자동 숨김 + 검수 플래그 기록.
  - [ ] 계정 삭제가 **비동기로 완료**되어 DB·Storage 전량 제거, 재로그인 불가, 진행 상태 표시.
  - [ ] 데이터 내보내기로 내 프로필·캐치 목록 다운로드.
  - [ ] 과도한 팔로우/좋아요/신고가 rate limit에 걸려 차단됨.

### Phase 6 — 수익화 (광고 + 코스메틱)
- AdMob: 피드 N개마다 **네이티브 광고**. **ATT 프롬프트** + **UMP 동의**(EU) 선행.
- StoreKit 2: 비소모성 코스메틱(항아리 스킨/배경/물리 이펙트 팩) 상품, 구매·복원. **영수증을 서버에서 검증(App Store Server API / JWS 트랜잭션 검증) 후** `entitlements` 기록 — 클라 신고만으로 권한 부여 금지.
- 코스메틱 적용: 항아리 배경/스티커 림/물리 파라미터 테마.
- **AC6**:
  - [ ] 앱 첫 실행류 시 ATT 요청, 거부 시 비개인화 광고로 동작(크래시·무한로딩 없음).
  - [ ] 피드에 네이티브 광고가 N번째마다 1회 삽입.
  - [ ] 코스메틱 구매→즉시 적용, 앱 재설치·타기기에서 "구매 복원"으로 복원, `entitlements` 반영.
  - [ ] StoreKit 외 외부 결제 미사용(App Store 정책 준수).

### Phase 7 — 출시 준비
- 개인정보 영양성분표(수집 항목), ATT 사용 목적 문구, **연령등급(UGC → 17+ 가능성)**.
- **푸시 알림**(팔로우/좋아요 — 소셜 리텐션 핵심, 선택 아님): APNs + Supabase/Edge 트리거.
- **딥링크/유니버설 링크**: 프로필·캐치 공유(SNS 바이럴 경로).
- 빈 상태/로딩/에러 UX, 앱 아이콘·스토어 스크린샷.
- **AC7**: TestFlight 업로드 성공, 심사 체크리스트(계정삭제·ATT·StoreKit 전용·Sign in with Apple·UGC 1.2) 충족, 공유 링크가 앱으로 딥링크.

---

## 4. Risks & Mitigations

| 리스크 | 영향 | 완화 |
|--------|------|------|
| **공개 UGC 사진 → 안전·법적 리스크** | 부적절 콘텐츠, 신고, 심사 거절 | 신고/차단 필수, 민감콘텐츠 점검, 모더레이션 큐, 명확한 ToS·연령등급, 기본공개지만 즉시 비공개 전환 제공 |
| **RLS 누락으로 비공개 캐치 유출** | 프라이버시 사고 | 비공개=비공개 강제하는 RLS·Storage 정책을 Phase0에 먼저, 피드/스토리지 양쪽 테스트(공개/비공개/차단 매트릭스) |
| **App Store 심사 규정** | 출시 지연 | 계정삭제·ATT·Sign in with Apple·StoreKit 전용 결제를 로드맵에 명시적 포함(Phase5/6) |
| **팔로잉 전용 피드 → 신규 유저 빈 피드** | 초기 이탈 | 온보딩에서 추천/검색 유도, 빈 상태 카피, (선택)시드 추천 유저 |
| **이미지 스토리지 비용/남용** | 비용·악용 | 업로드 1024px 상한·용량 제한·rate limit, 비공개 버킷+서명 URL |
| **읽기시점 피드 팬아웃 확장성** | 팔로잉 많을 때 지연 | 초기 인덱스 쿼리로 충분, 부하 시 피드 테이블(쓰기시점 팬아웃)·캐시로 전환 |
| **로컬→클라우드 마이그레이션** | 기존 로컬 수집 유실 | 최초 로그인 시 로컬 `manifest.json` 캐치를 1회 업로드 마이그레이션 |
| **Supabase 키 노출** | 보안 | anon key만 클라이언트, 민감 작업은 RLS/Edge Function. service_role 키 절대 번들 금지 |

---

## 5. Verification Steps
1. **마이그레이션**: `supabase db reset` 후 모든 테이블·RLS·인덱스 생성 확인.
2. **인증**: 신규 Apple 로그인→profiles 생성→세션 복원→로그아웃→재로그인.
3. **가시성 매트릭스**: (공개/비공개 캐치) × (본인/팔로워/비팔로워/차단) 조합에서 피드·프로필·Storage 노출이 정책과 일치.
4. **동기화**: 기기 A에서 Catch → 기기 B 동일 계정에 반영.
5. **소셜**: 팔로우/언팔/검색/차단 동작 + 카운트 정확.
6. **피드**: 팔로잉 캐치만, 시간순, 페이지네이션, 좋아요 유지.
7. **폴더**: 배정/공개토글/삭제 시 이동.
8. **모더레이션**: 신고·차단·계정삭제 후 데이터·스토리지 제거 확인.
9. **수익화**: ATT 흐름, 네이티브 광고 삽입, 코스메틱 구매·복원·entitlement 동기화.
10. **심사 체크리스트**: 계정삭제·ATT 문구·Sign in with Apple·StoreKit 전용.

---

## 6. 열린 결정 (실행 전 확인 권장)
- **Supabase 호스팅**: 클라우드 프로젝트(권장) vs 셀프호스팅. (클라우드 가정으로 진행)
- **피드 아이템 단위**: 개별 캐치(권장, 즉각성) vs "오늘의 수집 묶음"(요약형). 기본=개별 캐치.
- **민감콘텐츠 점검 깊이**: 사후 신고만(MVP) vs 업로드시 `SensitiveContentAnalysis` 차단(권장, 단 실기기/iOS 17+).
- **로컬 수집 마이그레이션 제공 여부**: 기존 로컬 캐치를 첫 로그인에 업로드할지(권장).
- **코스메틱 1차 상품 구성**: 항아리 배경 / 스티커 림 / 물리 이펙트 중 출시 SKU.
- **앱 번들 ID 유지**: `com.catch.app` 그대로 vs 신규(소셜 분리). 유지 가정.

---

## 7. Critic 리뷰 반영 changelog (REVISE → 적용)
> `oh-my-claudecode:critic` 리뷰. 아키텍처·참조 정확, 단 프라이버시/심사에서 CRITICAL 1 + MAJOR 6.

**CRITICAL (반영)**
- 모더레이션(신고·차단·콘텐츠필터)을 Phase 5→**Phase 1로 당김** — 기본 전체 공개가 Phase 1에서 시작하므로 UGC 출시 게이트(App Store 1.2) 충족.

**MAJOR (전부 반영)**
1. 서명 URL **TTL 5~15분** 명시 + 비공개 전환 후 잔존(즉시 무효화 불가) 한계 문서화, 민감시 프록시 엔드포인트 대안(§Storage).
2. **폴더/캐치 가시성 합성 규칙** 명시 — 공개 캐치라도 비공개 폴더면 숨김, RLS folders JOIN(§2.5).
3. **차단 양방향 RLS 배제** — catches/profiles/follows/feed에 `NOT EXISTS(blocks…)`, 직접 id 우회 차단(§2.5).
4. **like_count** 트리거 전용 갱신 + 클라 UPDATE RLS 차단(데이터 모델).
5. **EXIF/GPS 명시 제거** + 검증(Phase 1 AC).
6. **username 검증**(`^[a-z0-9_]{3,20}$`, 예약어, 변경 쿨다운, CHECK).

**MINOR/누락 반영**: 피드 인덱스에 `is_public` 추가, **커서 기반 페이지네이션**(Phase 3), `handle_new_user` 트리거로 profiles 생성, `entitlements` **서버 영수증 검증**(Phase 6), `updated_at` 컬럼, **푸시 알림·딥링크**를 정식 범위로(Phase 7), **rate limiting·GDPR export·비동기 계정삭제**(Phase 5), 로컬→클라우드 마이그레이션 멱등(Phase 1).
