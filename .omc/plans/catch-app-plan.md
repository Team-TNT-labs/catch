# Catch — iPhone 스티커 수집 앱 작업 계획

> 카메라로 사물을 찍어 자동 누끼(배경 제거)한 뒤, **Catch** 버튼으로 스티커를 영구 저장하고,
> 저장된 스티커들이 구슬처럼 중력을 받아 바닥에 쌓이며 기울임·흔들기·던지기로 가지고 노는 앱.

---

## 1. Requirements Summary

### 확정 결정 (사용자 인터뷰)
| 항목 | 결정 |
|------|------|
| 플랫폼 | iPhone 전용, 네이티브 |
| 스택 | SwiftUI + AVFoundation + Vision + SpriteKit + CoreMotion |
| 누끼 | 온디바이스 Vision (`VNGenerateForegroundInstanceMaskRequest`, iOS 17+) |
| 저장 | 영구 저장 (PNG 파일 + JSON 매니페스트) |
| 물리 충돌 | **실루엣 외곽 충돌** — `SKPhysicsBody(texture:alphaThreshold:size:)` |
| 인터랙션 | ① 폰 기울임 굴림(자이로) ② 흔들면 섞임 ③ 드래그 & 던지기 |
| 최소 iOS | **iOS 17.0** (Vision 피사체 마스크 API + SpriteView 안정 + 최신 기기 커버리지) |

### 핵심 사용자 흐름
1. 홈 = 스티커 더미(물리 화면). 우상단/하단에 카메라 버튼.
2. 카메라 버튼 → 촬영 화면 → 셔터.
3. 촬영 즉시 Vision으로 피사체 누끼 → 투명 배경 컷아웃 프리뷰.
4. **Catch** 버튼 → PNG로 영구 저장 → 홈으로 복귀하며 새 구슬이 위에서 떨어져 더미에 합류.
5. 홈에서 기울이면 구슬이 굴러가고, 흔들면 섞이고, 드래그해서 던질 수 있음.
6. 앱 재실행 시 저장된 스티커가 다시 바닥에 쌓인 상태로 로드.

---

## 2. Acceptance Criteria (테스트 가능)

- [ ] **AC1 카메라**: 카메라 권한 허용 후 실시간 프리뷰가 보이고, 셔터로 정지 이미지를 캡처한다. 권한 거부 시 설정 유도 안내가 표시된다.
- [ ] **AC2 누끼 정확도**: 단일 피사체(컵, 인형 등)를 찍으면 배경이 제거된 투명 PNG가 생성되고, 피사체 외곽 기준으로 crop되어 여백이 최소화된다. (육안 검증: 배경 픽셀 alpha=0)
- [ ] **AC3 누끼 실패 처리**: 피사체를 못 찾으면(마스크 0개) "피사체를 찾지 못했어요" 안내 후 재촬영 가능. 앱은 크래시하지 않는다.
- [ ] **AC4 Catch 저장**: Catch 누르면 PNG가 `Documents/stickers/<uuid>.png`에 저장되고 매니페스트에 메타데이터(id, filename, createdAt)가 append 된다.
- [ ] **AC5 영구성**: 앱 강제 종료 후 재실행하면 저장된 모든 스티커가 물리 화면에 다시 쌓인 상태로 나타난다.
- [ ] **AC6 실루엣 충돌**: 두 스티커가 겹치지 않고 각자의 불투명 외곽선 기준으로 부딪혀 쌓인다. (원형이 아니라 모양대로 맞물림 — 육안 검증)
- [ ] **AC7 자이로 중력**: 기기를 좌/우/뒤로 기울이면 0.3초 내에 구슬들이 그 방향으로 굴러간다.
- [ ] **AC8 흔들기 섞임**: 기기를 흔들면 모든 구슬에 임펄스가 가해져 튀어오르며 위치가 재배치된다.
- [ ] **AC9 드래그 & 던지기**: 구슬을 손가락으로 끌 수 있고, 빠르게 놓으면 손가락 속도에 비례해 관성으로 날아간다.
- [ ] **AC10 성능**: 스티커 30개 기준 60fps(최소 50fps) 유지, 물리 바디 생성으로 인한 UI 프리즈 없음(백그라운드 스레드 생성).
- [ ] **AC11 개별 삭제**: 스티커를 길게 누르면(0.5s, 이동 없음) 삭제되고, 디스크 파일·매니페스트에서 제거되어 앱 재실행 시 다시 나타나지 않는다.

---

## 3. Architecture & 파일 구조

XcodeGen으로 프로젝트를 CLI에서 재현 가능하게 생성(Xcode GUI 없이 빌드 가능). 대안: Xcode에서 직접 App 템플릿 생성.

```
catch/
├── project.yml                    # XcodeGen 설정 (deployment target iOS 17.0)
├── Catch/
│   ├── CatchApp.swift             # @main, 진입점
│   ├── Info.plist                 # NSCameraUsageDescription, 세로 고정
│   ├── Models/
│   │   └── Sticker.swift          # Codable: id, filename, createdAt
│   ├── Services/
│   │   ├── CameraController.swift     # AVCaptureSession 래퍼 (still capture)
│   │   ├── BackgroundRemovalService.swift  # Vision 누끼
│   │   ├── StickerStore.swift         # 파일 저장 + 매니페스트(JSON) CRUD
│   │   └── MotionService.swift        # CoreMotion → 중력 벡터 퍼블리시
│   ├── Views/
│   │   ├── HomeView.swift             # SpriteView 호스팅 + 카메라 버튼
│   │   ├── CameraView.swift           # UIViewRepresentable 프리뷰 + 셔터
│   │   └── CutoutPreviewView.swift    # 누끼 결과 + Catch 버튼
│   ├── Physics/
│   │   └── StickerScene.swift         # SKScene: 중력/벽/구슬/드래그/흔들기
│   └── Assets.xcassets
└── .omc/plans/catch-app-plan.md
```

### 데이터 모델
```swift
struct Sticker: Codable, Identifiable {
    let id: UUID
    let filename: String      // "<uuid>.png"
    let createdAt: Date
}
```
매니페스트: `Documents/stickers/manifest.json` = `[Sticker]`. PNG: `Documents/stickers/<id>.png`.
(대안: SwiftData. 단순성·디버깅 용이성 위해 Codable JSON 채택, 마이그레이션 부담 없음.)

---

## 4. Implementation Steps

### Step 0 — 프로젝트 스캐폴딩
- `project.yml` 작성: target name `Catch`, platform iOS, deploymentTarget 17.0, bundleId, sources `Catch/`.
- `Info.plist`: `NSCameraUsageDescription` = "스티커를 만들기 위해 카메라를 사용해요", `UISupportedInterfaceOrientations` 세로만, `UILaunchScreen`.
- `xcodegen generate` → `Catch.xcodeproj` 생성. `CatchApp.swift`에 빈 `HomeView` 띄우고 빌드 통과 확인.
- **검증**: `xcodebuild -scheme Catch -destination 'generic/platform=iOS' build` 성공.

### Step 1 — 카메라 캡처 (`CameraController.swift`, `CameraView.swift`)
- `AVCaptureSession` + `AVCaptureDeviceInput`(후면) + `AVCapturePhotoOutput`.
- `CameraView`: `UIViewRepresentable`로 `AVCaptureVideoPreviewLayer` 호스팅, 셔터 버튼.
- `capturePhoto()` → `AVCapturePhotoCaptureDelegate` → `UIImage`/`CGImage` 반환(콜백 또는 async).
- 권한: **앱 진입 시 `AVCaptureDevice.authorizationStatus(for: .video)` 먼저 확인**.
  - `.notDetermined` → `requestAccess`로 최초 프롬프트.
  - `.denied`/`.restricted` → `requestAccess`는 다이얼로그를 안 띄우므로, "설정에서 카메라 권한을 켜주세요" 안내 + `UIApplication.openSettingsURLString` 딥링크.
- **검증 (AC1)**: 실기기에서 프리뷰·캡처 동작, **이전에 거부한 상태로 재실행 시 설정 유도 안내 표시**.

### Step 2 — 누끼 (`BackgroundRemovalService.swift`)
- 입력 `CGImage` → `VNImageRequestHandler` → `VNGenerateForegroundInstanceMaskRequest`.
- 결과 `VNInstanceMaskObservation.allInstances`에 대해
  `generateMaskedImage(ofInstances:from:croppedToInstancesExtent: true)` → 투명 배경 `CVPixelBuffer`.
- `CIImage` → `CIContext.createCGImage` → `UIImage`. 마스크 0개면 nil 반환(실패 신호).
- `generateMaskedImage`의 `CVPixelBuffer` 픽셀 포맷이 비표준이면 `createCGImage`가 alpha를 떨굴 수 있으니, 결과 PNG의 alpha 채널 보존을 **이 단계에서 우선 검증**.
- 무거운 작업은 background task로, 결과만 메인 스레드 전달.
- **검증 (AC2, AC3)**: 컵/인형 누끼 PNG alpha 확인, 빈 벽 촬영 시 실패 안내.

### Step 2.5 — 이미지 방향 정규화 (`BackgroundRemovalService.swift` 후처리) ⚠️ Critic MAJOR
- **문제**: `SKTexture(image:)`는 `UIImage.imageOrientation`(카메라 EXIF 회전 메타데이터)을 무시함. UIKit 좌표계는 좌상단 원점, SpriteKit은 좌하단 원점 → 누끼 결과가 물리 씬에서 회전/뒤집혀 보임. **첫 촬영부터 100% 재현되는 버그.**
- **해결**: 누끼 `UIImage`를 `UIGraphicsImageRenderer`로 새 컨텍스트에 다시 그려 픽셀 데이터가 시각 방향과 일치하도록 정규화한 뒤 저장/텍스처화. (이후 `SKTexture(image:)`는 항상 정규화된 이미지만 받음)
- **검증**: 가로/세로/뒤집어 촬영한 3종이 물리 씬에서 모두 올바른 방향으로 표시.

### Step 3 — Catch 프리뷰 & 저장 (`CutoutPreviewView.swift`, `StickerStore.swift`)
- `CutoutPreviewView`: 누끼 `UIImage` 표시, **Catch** / 다시찍기 버튼.
- `StickerStore.save(image:)`: **방향 정규화된**(Step 2.5) PNG 인코딩 → `Documents/stickers/<uuid>.png` 기록 + **바디용 256px 다운스케일 PNG도 함께 캐시**(`<uuid>_body.png`), `manifest.json` 갱신, 새 `Sticker` 반환.
- `StickerStore.loadAll()` / `.delete(id:)` 구현.
- **검증 (AC4, AC5)**: Catch 후 파일 존재, 앱 재실행 시 매니페스트 로드.

### Step 4 — 물리 씬 기본 (`StickerScene.swift`, `HomeView.swift`)
- `HomeView`에 `SpriteView(scene:)` 풀스크린 + 카메라 버튼 오버레이.
  - **오버레이 버튼은 별도 `ZStack` 레이어로, 비-상호작용 영역은 `.allowsHitTesting(false)`** — 안 그러면 SwiftUI 오버레이가 터치를 먹어 드래그가 일부 영역에서 안 먹음(Critic MAJOR #3 연계).
- `StickerScene`: `scaleMode = .resizeFill`, **`anchorPoint = CGPoint(x: 0, y: 0)`** ⚠️ Critic MAJOR.
  - 기본 `anchorPoint`은 `(0.5, 0.5)`(중앙 원점)인데 `SKPhysicsBody(edgeLoopFrom: frame)`은 좌하단 원점을 가정 → 안 맞추면 벽이 화면 밖으로 어긋남. notch/Dynamic Island safe area도 벽 위치 계산 시 고려.
  - `physicsBody = SKPhysicsBody(edgeLoopFrom: frame)`(바닥·좌우·상단 벽). 중력은 SpriteKit 기본값이 이미 `(0, -9.8)`이라 별도 설정 불필요(Step 6에서 자이로로 덮어씀).
- `addSticker(_:)`: 정규화된 이미지로 `SKTexture(image:)` → `SKSpriteNode`. **표시 크기 정규화**: 긴 변을 일정 범위(예: 120~150pt)로 스케일 — 촬영 거리에 따라 픽셀 크기가 제각각이라 정규화 없으면 더미가 들쭉날쭉(Critic gap).
- `loadAll()` 결과 투하: **동시 생성 금지**. 화면 상단을 따라 x를 분산 + 작은 랜덤 지연을 줘 순차 낙하 — 같은 위치에 30개가 한꺼번에 겹치면 물리 폭발(scatter)함(Critic ambiguity).
- **검증**: 구슬들이 떨어져 바닥에 쌓임(원형 임시 바디로 먼저 확인), 벽이 화면 가장자리에 정확히 위치.

### Step 5 — 실루엣 충돌 바디 (AC6)
- `SKPhysicsBody(texture: tex, alphaThreshold: 0.5, size: tex.size())`로 외곽 폴리곤 생성.
- 생성 비용 큰 작업이므로 바디용 텍스처를 긴 변 256px로 다운스케일해 사용(표시는 정규화 원본).
  - **다운스케일 이미지는 Catch 저장 시점(`StickerStore`)에 한 번 만들어 디스크에 캐시** — 매 앱 실행 시 재생성하면 낭비(Critic minor #6).
- `restitution` 낮게(0.1), `friction` 적당히(0.4)로 쌓임 안정화. `allowsRotation = true`.
- **폴백**: 256px에서도 너무 무거우면 convex hull 또는 bounding box 바디로 단계적 강등(노드 수 많을 때).
- **검증 (AC6)**: 비대칭 물체 두 개가 모양대로 맞물려 쌓임.

### Step 6 — 자이로 중력 (`MotionService.swift`, AC7)
- `CMMotionManager.startDeviceMotionUpdates` → `deviceMotion.gravity` (x,y,z).
- 매 업데이트 `scene.physicsWorld.gravity = CGVector(dx: g.x * 9.8, dy: g.y * 9.8)` (세로 고정 기준 부호 보정).
- **검증 (AC7)**: 좌우/뒤로 기울이면 굴러감.

### Step 7 — 흔들기 섞임 & 드래그/던지기 (AC8, AC9)
- **흔들기 (단일 방식 확정)**: `CMMotionManager.userAcceleration` 크기(magnitude) 임계값 초과 감지 → 전체 노드에 랜덤 `applyImpulse`.
  - ⚠️ `motionEnded(.motionShake)`는 쓰지 않음 — `SpriteView`에 올린 `SKScene`은 first responder가 되지 않아 UIKit motion 이벤트가 전달되지 않고 **조용히 안 터짐**(Critic MAJOR #2). 이미 도는 `MotionService`(Step 6)에 흔들기 감지를 통합.
- **드래그 (단일 전략 확정)**: `touchesBegan`에서 노드 히트테스트 → 잡는 순간 **`physicsBody.isDynamic = false`**(물리 분리). `touchesMoved`로 `node.position` 직접 이동(바디·노드 desync/텔레포트 방지). `touchesEnded`에서 `isDynamic = true` 복원 + 최근 `Δposition/Δtime`로 산출한 속도(상한 클램프)를 `physicsBody.velocity`로 적용해 관성 던지기.
- **길게 눌러 개별 삭제 (확정 결정)**: 노드를 누른 채 일정 시간(예: 0.5s) 이동 없이 유지하면 삭제 모드 — 흔들림 애니메이션 + 가벼운 햅틱 후 해당 노드 제거 & `StickerStore.delete(id:)`(원본·바디·매니페스트 정리). 드래그와 구분: 임계 거리 이상 움직이면 드래그로 전환, 그 이하로 멈춰 있으면 long-press 타이머 발동.
- **검증 (AC8, AC9, AC11)**: 흔들면 튀고, 끌어서 던지면 날아감(텔레포트 없음), 길게 누르면 삭제되고 재실행 시 안 돌아옴.

### Step 8 — 성능 튜닝 & 마감 (AC10)
- **스레딩(정정)**: `SKPhysicsBody(texture:)`는 텍스처/GPU 시스템에 접근하며 Apple이 스레드 안전을 보장하지 않음. 따라서 백그라운드에선 **다운스케일 `CGImage`까지만** 만들고, `SKPhysicsBody`·`SKTexture`·노드 추가는 **메인 스레드**에서(UI 프리즈는 이미지 디코드/리사이즈를 오프로드해 방지).
- 정지 바디 자동 sleep 활용, 30개 기준 fps 측정(`SKView.showsFPS`).
- **메모리**: 30+ 풀해상도 `SKTexture` 동시 상주 시 GPU 메모리 부담. 표시용 텍스처도 정규화 크기(≤150pt 상당)로 유지하고, 메모리 경고(`didReceiveMemoryWarning`) 시 화면 밖 텍스처 해제 고려.
- 빈 상태 안내, 카메라 버튼 디자인, 앱 아이콘.
- (선택) 길게 눌러 삭제 또는 전체 비우기 — 인터뷰 미선택, **별도 결정 필요**(아래 리스크 참고).

---

## 5. Risks & Mitigations

| 리스크 | 영향 | 완화 |
|--------|------|------|
| `SKPhysicsBody(texture:)`가 복잡/오목 형상에서 비싸고 부정확 | fps 저하, 충돌 튐 | 바디용 텍스처 다운스케일(≤256px), alphaThreshold 튜닝, 백그라운드 생성, 노드 수 상한·sleep |
| Vision 누끼는 iOS 17+ 전용 | 구형 기기 미지원 | 최소 타깃 17.0 명시, App Store 자동 필터링 |
| 시뮬레이터엔 카메라/모션 없음 | 핵심 기능 검증 불가 | 카메라·자이로·흔들기는 **실기기 필수**, 시뮬레이터는 갤러리 임포트 디버그 경로(개발용)로 보완 |
| 영구 저장만 있고 삭제 UX 미선택 | 구슬 무한 누적 → 성능·혼잡 | Step 8에서 길게 눌러 삭제 또는 "전체 비우기" 추가 여부 **사용자 확인 필요** |
| 던지기 속도 계산이 SpriteKit 좌표/시간과 어긋남 | 던지기 부자연 | `touchesMoved` 사이 Δposition/Δtime로 속도 산출, 상한 클램프 |
| Catch 후 큰 PNG 다수 저장 | 디스크·로딩 비용 | 적정 해상도로 리사이즈 저장(예: 긴 변 1024px), 썸네일 분리 고려 |

---

## 6. Verification Steps

1. **빌드**: `xcodegen generate && xcodebuild -scheme Catch -destination 'generic/platform=iOS' build` 성공.
2. **실기기 스모크(iOS 17+)**: 촬영→누끼→Catch→홈 복귀 1사이클 정상, 새 구슬 낙하 확인.
3. **누끼 품질**: 서로 다른 물체 3종 촬영, 배경 alpha=0·외곽 crop 확인 (AC2).
4. **실패 경로**: 빈 벽 촬영 → 실패 안내, 무크래시 (AC3).
5. **영구성**: 5개 Catch 후 앱 종료·재실행 → 5개 재로딩 (AC5).
6. **실루엣 충돌**: 비대칭 물체끼리 모양대로 맞물림 육안 확인 (AC6).
7. **모션**: 기울임 굴림·흔들기 섞임·드래그 던지기 각각 동작 (AC7~9).
8. **성능**: `showsFPS`로 30개 기준 ≥50fps, 바디 생성 시 프리즈 없음 (AC10).

---

## 7. 열린 결정
- **삭제 UX**: ✅ **확정 — 길게 눌러 개별 삭제** (Step 7, AC11 반영).
- **프로젝트 생성 방식**: XcodeGen(CLI 재현·권장) vs Xcode GUI 템플릿. 환경에 `xcodegen` 미설치면 `brew install xcodegen` 필요.
- **저장 해상도 상한**: 원본 그대로 vs 긴 변 1024px 리사이즈(권장).

---

## 8. Critic 리뷰 반영 changelog (REVISE → 적용 완료)
> `oh-my-claudecode:critic` THOROUGH 리뷰. **명명된 Apple API 5종은 모두 검증 통과(정확)**. 아래 항목 반영.

**MAJOR (실행 전 필수, 모두 반영):**
1. 이미지 방향 정규화 — **Step 2.5 신설** (`SKTexture`가 `UIImage.imageOrientation` 무시 → `UIGraphicsImageRenderer` 재렌더)
2. 흔들기 — `motionEnded` 제거, `CMMotionManager.userAcceleration` 단일 방식 확정 (Step 7)
3. 드래그 — `isDynamic=false` 단일 전략 확정 + 오버레이 `.allowsHitTesting(false)` (Step 4·7)
4. `anchorPoint = (0,0)` 명시 — `edgeLoopFrom: frame` 벽 위치 정합 (Step 4)

**MINOR/Gap (반영):** 다운스케일 바디 이미지 저장 시점 캐시(Step 3·5), 물리 바디 생성 메인 스레드 정정(Step 8), 중복 gravity 라인 제거(Step 4), 스티커 표시 크기 정규화(Step 4), 이미 거부된 카메라 권한 처리(Step 1), 동시 투하 → 분산·지연(Step 4), 메모리 경고 처리(Step 8), alpha 채널 조기 검증(Step 2).

**미반영(범위상 보류):** 시뮬레이터 갤러리 임포트 디버그 경로 — 실기기 검증으로 갈음, 필요 시 별도 추가.
