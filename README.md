# Catch

카메라로 사물을 찍으면 자동으로 누끼(배경 제거)를 따 스티커로 만들고, 저장된 스티커들이 구슬처럼 중력을 받아 바닥에 쌓이는 iPhone 앱.

## 기능
- 📷 카메라 촬영 → 온디바이스 Vision으로 자동 누끼
- 🔦 스캐너 라인이 위아래로 훑으며 그 자리에서 피사체가 드러나는 연출
- 🫳 **Catch** 버튼으로 스티커 영구 저장(PNG + 매니페스트)
- 🌀 SpriteKit 물리 — 실루엣 외곽 충돌, 자이로 기울임 굴림 / 흔들면 섞임 / 드래그 던지기
- 🗑️ 길게 눌러 개별 삭제

## 스택
SwiftUI · AVFoundation · Vision · SpriteKit · CoreMotion (iOS 17+)

## 빌드
프로젝트는 [XcodeGen](https://github.com/yonaskolb/XcodeGen)으로 생성한다.

```bash
xcodegen generate
open Catch.xcodeproj
```

카메라·자이로·흔들기는 실기기에서만 동작한다(시뮬레이터엔 카메라/모션 없음).
