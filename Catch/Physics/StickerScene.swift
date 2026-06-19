import SpriteKit
import UIKit

/// 스티커들이 구슬처럼 중력으로 쌓이는 물리 씬.
/// - 실루엣 외곽 충돌(SKPhysicsBody(texture:))
/// - 자이로 중력 / 흔들기 섞임 / 드래그·던지기 / 길게 눌러 삭제
final class StickerScene: SKScene {
    private let motion = MotionService()

    /// 스티커를 잡았는지(true)/놓았는지(false) 알린다.
    var onGrabChanged: ((Bool) -> Void)?
    /// 길게 누르면 삭제를 '요청'한다(즉시 삭제 X). 호스트가 확인 후 `vanish(id:)`로 실제 삭제.
    var onRequestDelete: ((UUID) -> Void)?
    /// 스티커를 가볍게 탭하면 해당 캐치 id를 알린다(호스트가 포커스 프리뷰).
    var onTapCatch: ((UUID) -> Void)?
    /// 폴더 노드를 탭하면 해당 폴더 id를 알린다(호스트가 폴더 진입).
    var onOpenFolder: ((UUID) -> Void)?
    /// 스티커를 폴더 위로 드롭하면 (스티커 id, 폴더 id)를 알린다(호스트가 폴더 배정).
    var onDropOnFolder: ((UUID, UUID) -> Void)?
    /// 폴더를 길게 누르면 해당 폴더 id를 알린다(호스트가 편집 시트).
    var onEditFolder: ((UUID) -> Void)?
    /// 폴더 안에서 스티커를 뒤로가기 영역에 드롭하면 폴더 밖(미분류)으로 빼라고 알린다.
    var onEjectSticker: ((UUID) -> Void)?
    /// 폴더 안에서 스티커가 뒤로가기 영역 위에 올라왔는지(호스트가 버튼 하이라이트).
    var onEjectHover: ((Bool) -> Void)?
    /// 폴더 안일 때만 eject 활성(루트에선 끔).
    var ejectEnabled = false

    private var ejectHovered = false

    /// 좌상단 뒤로가기 버튼 근처 영역(씬 좌표, y 위쪽).
    private func inEjectZone(_ p: CGPoint) -> Bool {
        p.x < 110 && p.y > size.height - 120
    }

    // 폴더 노드 식별 — 이름 접두사 "F:".
    private func isFolder(_ node: SKNode) -> Bool { node.name?.hasPrefix("F:") ?? false }
    private func folderId(_ node: SKNode) -> UUID? {
        guard let n = node.name, n.hasPrefix("F:") else { return nil }
        return UUID(uuidString: String(n.dropFirst(2)))
    }
    private func catchId(_ node: SKNode) -> UUID? {
        guard let n = node.name, !n.hasPrefix("F:") else { return nil }
        return UUID(uuidString: n)
    }

    private let displayMaxDimension: CGFloat = 140

    /// 스티커가 많아질수록 새 스티커를 약간 작게(항아리가 넘치지 않게). 14개부터 줄이고 최소 96.
    private func crowdDisplayMax(for count: Int) -> CGFloat {
        guard count > 14 else { return displayMaxDimension }
        return max(96, displayMaxDimension - CGFloat(count - 14) * 3)
    }

    /// 하단 툴바(가운데 알약) 충돌 바디 — 스티커가 바에 가려지지 않게 부딪힘.
    /// (width, height, bottomMargin) — 씬 좌표 기준, 가로 중앙 정렬.
    var toolbarBarrier: (width: CGFloat, height: CGFloat, bottomMargin: CGFloat)? {
        didSet { rebuildToolbarBarrier() }
    }
    private var barrierNode: SKNode?

    /// 그리드 정렬 모드(중력 off, 터치 비활성).
    private(set) var isGrid = false
    /// 둥둥 떠다니는 모드(중력 0 + 잔잔한 표류).
    private(set) var floating = false

    // 드래그 상태
    private var draggedNode: SKSpriteNode?
    private weak var hoveredFolder: SKNode?   // 드래그 중 위에 올라온 폴더(하이라이트)
    private var dragStartPoint: CGPoint = .zero
    private var lastDragPoint: CGPoint = .zero
    private var lastDragTime: TimeInterval = 0
    private var dragStartTime: TimeInterval = 0
    private var dragVelocity: CGVector = .zero
    private var dragMoved = false

    // 길게 눌러 삭제 — Timer 대신 SKAction(런루프 tracking 모드에도 동작).
    private let longPressKey = "longPress"
    private let longPressDuration: TimeInterval = 0.5
    private let dragThreshold: CGFloat = 12

    private func cancelLongPress() { removeAction(forKey: longPressKey) }

    private var bgNode: SKSpriteNode?
    private var lastGravity = CGVector(dx: 0, dy: -9.8)   // 중력 데드존 기준(떨림 방지)

    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = 120   // ProMotion에서 부드럽게
        backgroundColor = Theme.sceneTop
        scaleMode = .resizeFill
        anchorPoint = .zero
        rebuildBackground()
        rebuildWalls()
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)

        motion.onGravity = { [weak self] vector in
            DispatchQueue.main.async {
                guard let self else { return }
                let g: CGVector = self.floating ? .zero : vector   // float 모드는 중력 무시
                // 데드존: 미세한 자이로 노이즈로 매 프레임 갱신하면 바디가 못 쉬고 바들바들 떤다.
                // 의미 있는 기울임(>0.3)일 때만 적용해, 가만히 있으면 안정되게.
                if abs(g.dx - self.lastGravity.dx) + abs(g.dy - self.lastGravity.dy) > 0.3 {
                    self.physicsWorld.gravity = g
                    self.lastGravity = g
                }
            }
        }
        motion.onShake = { [weak self] in
            DispatchQueue.main.async { self?.shuffle() }
        }
        motion.start()
    }

    deinit { motion.stop() }

    /// 매 프레임 각속도/속도를 클램프 — 충돌이 쌓여도 미친듯이 돌거나 튀지 않게.
    override func update(_ currentTime: TimeInterval) {
        let maxAngular: CGFloat = 4.0
        let maxSpeed: CGFloat = 1400
        for case let node as SKSpriteNode in children {
            guard let b = node.physicsBody, node !== draggedNode else { continue }
            if abs(b.angularVelocity) > maxAngular {
                b.angularVelocity = b.angularVelocity < 0 ? -maxAngular : maxAngular
            }
            let v = b.velocity
            let speed = hypot(v.dx, v.dy)
            if speed > maxSpeed {
                let r = maxSpeed / speed
                b.velocity = CGVector(dx: v.dx * r, dy: v.dy * r)
            }
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        rebuildBackground()
        rebuildWalls()
        rebuildToolbarBarrier()
    }

    private func rebuildToolbarBarrier() {
        barrierNode?.removeFromParent()
        barrierNode = nil
        guard let b = toolbarBarrier, size.width > 1, size.height > 1 else { return }
        let node = SKNode()
        node.position = CGPoint(x: size.width / 2, y: b.bottomMargin + b.height / 2)
        let body = SKPhysicsBody(rectangleOf: CGSize(width: b.width, height: b.height))
        body.isDynamic = false
        body.friction = 0.4
        node.physicsBody = body
        addChild(node)
        barrierNode = node
    }

    private func rebuildBackground() {
        guard size.width > 1, size.height > 1 else { return }
        bgNode?.removeFromParent()
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [Theme.sceneTop.cgColor, Theme.sceneBottom.cgColor] as CFArray
            guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors, locations: [0, 1]) else { return }
            cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0),
                                  end: CGPoint(x: 0, y: size.height), options: [])
        }
        let node = SKSpriteNode(texture: SKTexture(image: image))
        node.anchorPoint = .zero
        node.position = .zero
        node.zPosition = -10
        addChild(node)
        bgNode = node
    }

    private func rebuildWalls() {
        // 레이아웃 전 size가 0인 순간에 체인을 만들면 Box2D가 크래시하므로 가드.
        guard size.width > 1, size.height > 1 else {
            physicsBody = nil
            return
        }
        // 사방을 닫은 박스 — 스티커가 화면 밖으로 새어나가지 않게(특히 float/던지기).
        let body = SKPhysicsBody(edgeLoopFrom: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        body.friction = 0.4
        physicsBody = body
    }

    // MARK: - Spawning

    /// 캐치 1개를 물리 항아리에 투하한다.
    /// 무거운 테두리 생성은 호스트가 백그라운드에서 끝내 `bordered`/`working`을 넘긴다(메인 렉 방지).
    func addCatch(id: UUID, bordered: UIImage, working: UIImage, body: UIImage) {
        addStickerNode(bordered: bordered, working: working, bodyImage: body, id: id)
    }

    /// id로 스티커 노드를 즉시 제거(그리드에서 삭제 시).
    func removeNode(id: UUID) {
        childNode(withName: id.uuidString)?.removeFromParent()
    }

    /// 폴더를 모양 노드로 항아리에 투하한다(스티커처럼 떨어져 쌓임).
    func addFolder(id: UUID, name: String, shape rawShape: Int? = nil, color: Int? = nil) {
        let shape = FolderShape.resolve(rawShape, id: id)
        let image = shape.image(name: name, fill: FolderPalette.uiColor(color))
        let node = SKSpriteNode(texture: SKTexture(image: image))
        node.name = "F:" + id.uuidString

        let maxDim: CGFloat = 132
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 0 ? min(1, maxDim / longest) : 1
        let displaySize = CGSize(width: max(1, image.size.width * scale),
                                 height: max(1, image.size.height * scale))
        node.size = displaySize

        let body = shape.physicsBody(displaySize: displaySize)
        body.restitution = 0.02; body.friction = 0.6
        body.linearDamping = 0.3; body.angularDamping = 0.8
        body.allowsRotation = true; body.isDynamic = true
        body.usesPreciseCollisionDetection = true   // 벽 뚫고 사라짐 방지
        node.physicsBody = body

        let half = displaySize.width / 2
        node.position = CGPoint(x: .random(in: half...max(half, size.width - half)),
                                y: size.height - displaySize.height)
        node.zRotation = .random(in: -0.2...0.2)
        addChild(node)
    }

    /// 폴더 노드 즉시 제거.
    func removeFolderNode(id: UUID) {
        childNode(withName: "F:" + id.uuidString)?.removeFromParent()
    }

    /// 항아리를 비운다(폴더 전환 시).
    func clearAll() {
        cancelTimers()
        for case let node as SKSpriteNode in children where node.physicsBody != nil {
            node.removeFromParent()
        }
        draggedNode = nil
    }

    private func cancelTimers() {
        cancelLongPress()
    }

    private func addStickerNode(bordered: UIImage, working: UIImage, bodyImage: UIImage, id: UUID) {
        let texture = SKTexture(image: bordered)
        let node = SKSpriteNode(texture: texture)
        node.name = id.uuidString

        // 표시 크기 정규화: 긴 변을 (혼잡도 반영) 최대 치수 이하로.
        let maxDim = crowdDisplayMax(for: stickerNodes.count)   // 많을수록 약간 작게
        let longest = max(bordered.size.width, bordered.size.height)
        let scale = longest > 0 ? min(1, maxDim / longest) : 1
        let displaySize = CGSize(width: max(1, bordered.size.width * scale),
                                 height: max(1, bordered.size.height * scale))
        node.size = displaySize

        // 물리 바디는 테두리를 뺀 내부 실루엣 기준.
        let innerW = bordered.size.width > 0 ? working.size.width / bordered.size.width : 1
        let innerH = bordered.size.height > 0 ? working.size.height / bordered.size.height : 1
        let bodySize = CGSize(width: displaySize.width * innerW, height: displaySize.height * innerH)
        // 바디 트레이스는 거친 텍스처로 — 폴리곤 정점이 줄어 충돌이 가볍고 지터가 적다.
        let bodyTexture = SKTexture(image: bodyImage.resized(maxDimension: 100))
        let body = SKPhysicsBody(texture: bodyTexture, alphaThreshold: 0.5, size: bodySize)
        body.restitution = 0.02            // 거의 안 튕김(정지 안정)
        body.friction = 0.6
        body.linearDamping = 0.3           // 충돌 후 속도 빨리 가라앉음
        body.angularDamping = 0.8          // 회전 빨리 잦아듦(지터 감소)
        body.allowsRotation = true
        body.isDynamic = true
        body.usesPreciseCollisionDetection = true   // 벽 뚫고 사라짐 방지
        node.physicsBody = body

        // 화면 안쪽 상단에서 낙하(상단을 닫았으므로 화면 밖에서 스폰하지 않음).
        let half = displaySize.width / 2
        let minX = half
        let maxX = max(half, size.width - half)
        node.position = CGPoint(x: .random(in: minX...maxX), y: size.height - displaySize.height)
        node.zRotation = .random(in: -0.3...0.3)
        addChild(node)
    }

    // MARK: - Shake

    func shuffle() {
        guard !isGrid else { return }
        for case let node as SKSpriteNode in children where node.physicsBody != nil {
            node.physicsBody?.applyImpulse(CGVector(dx: .random(in: -40...40), dy: .random(in: 20...90)))
            node.physicsBody?.applyAngularImpulse(.random(in: -0.05...0.05))
        }
    }

    // MARK: - Float (둥둥)

    /// 중력 0 + 잔잔한 표류 모드 토글.
    func setFloating(_ on: Bool) {
        floating = on
        if on {
            physicsWorld.gravity = .zero
            for case let node as SKSpriteNode in children where node.physicsBody != nil {
                node.physicsBody?.linearDamping = 0.9
                node.physicsBody?.angularDamping = 0.9
                node.physicsBody?.applyImpulse(CGVector(dx: .random(in: -12...12), dy: .random(in: -12...12)))
            }
            // 주기적으로 살짝 밀어 잔잔히 떠다니게.
            run(.repeatForever(.sequence([
                .run { [weak self] in self?.applyFloatDrift() },
                .wait(forDuration: 1.4)
            ])), withKey: "floatDrift")
        } else {
            removeAction(forKey: "floatDrift")
            for case let node as SKSpriteNode in children where node.physicsBody != nil {
                node.physicsBody?.linearDamping = 0.18
                node.physicsBody?.angularDamping = 0.6
            }
            physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)   // 모션이 곧 갱신
        }
    }

    private func applyFloatDrift() {
        for case let node as SKSpriteNode in children where node.physicsBody != nil && node !== draggedNode {
            node.physicsBody?.applyImpulse(CGVector(dx: .random(in: -9...9), dy: .random(in: -9...9)))
            node.physicsBody?.applyAngularImpulse(.random(in: -0.01...0.01))
        }
    }

    // MARK: - 그리드 정렬 / 중력 해제

    private var stickerNodes: [SKSpriteNode] {
        children.compactMap { $0 as? SKSpriteNode }
            .filter { ($0.name.flatMap { UUID(uuidString: $0) }) != nil }
    }

    /// 깔끔한 그리드로 정렬(중력 off).
    func arrangeGrid() {
        isGrid = true
        let nodes = stickerNodes
        let n = nodes.count
        guard n > 0, size.width > 1 else { return }

        let cols = max(2, min(4, Int(size.width / 150)))
        let rows = Int(ceil(Double(n) / Double(cols)))
        let topInset = deviceSafeAreaTop + 116
        let bottomInsetV = deviceSafeAreaBottom + 96
        let usableH = max(120, size.height - topInset - bottomInsetV)
        let cellW = size.width / CGFloat(cols)
        let cellH = min(cellW, usableH / CGFloat(max(1, rows)))
        let cell = min(cellW, cellH)
        let startX = cellW / 2
        let startY = size.height - topInset - cellH / 2

        for (i, node) in nodes.enumerated() {
            node.physicsBody?.isDynamic = false
            node.physicsBody?.velocity = .zero
            node.physicsBody?.angularVelocity = 0
            let c = i % cols, r = i / cols
            let x = startX + CGFloat(c) * cellW
            let y = startY - CGFloat(r) * cellH
            let longest = max(node.size.width, node.size.height)
            let target = longest > 0 ? (cell * 0.82) / longest : 1
            let action = SKAction.group([
                .move(to: CGPoint(x: x, y: y), duration: 0.4),
                .scale(to: target, duration: 0.4),
                .rotate(toAngle: 0, duration: 0.4, shortestUnitArc: true)
            ])
            action.timingMode = .easeInEaseOut
            node.run(action)
        }
    }

    /// 그리드 해제 → 다시 중력으로 떨어뜨림.
    func releaseGrid() {
        isGrid = false
        for node in stickerNodes {
            node.run(.scale(to: 1.0, duration: 0.25))
            node.physicsBody?.isDynamic = true
            node.physicsBody?.applyImpulse(CGVector(dx: .random(in: -25...25), dy: .random(in: -10...20)))
            node.physicsBody?.applyAngularImpulse(.random(in: -0.03...0.03))
        }
    }

    // MARK: - Touch: drag / throw / long-press delete

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        guard let node = nodes(at: location).first(where: { $0.physicsBody != nil }) as? SKSpriteNode else { return }

        draggedNode = node
        dragStartPoint = location
        lastDragPoint = location
        lastDragTime = CACurrentMediaTime()
        dragStartTime = CACurrentMediaTime()
        dragVelocity = .zero
        dragMoved = false

        guard !isGrid else { return }   // 그리드: 탭만 감지(드래그/삭제 없음)

        node.physicsBody?.isDynamic = false      // 드래그 중 물리 분리(desync 방지)
        // 드래그 중엔 충돌에서 완전히 제외(양방향) — 폴더를 밀어내거나 벽 밖으로 튕기지 않게.
        node.physicsBody?.collisionBitMask = 0
        node.physicsBody?.categoryBitMask = 0
        node.zPosition = 50                      // 맨 앞으로 — 폴더 위에 얹힌 채 끌리도록
        onGrabChanged?(true)                     // 잡는 동안 페이지 스크롤 잠금

        // 길게 누르면: 스티커=삭제 요청 / 폴더=편집 요청.
        cancelLongPress()
        run(.sequence([
            .wait(forDuration: longPressDuration),
            .run { [weak self, weak node] in
                guard let self, let node else { return }
                if self.isFolder(node) { self.requestEditFolder(node) }
                else { self.requestDelete(node) }
            }
        ]), withKey: longPressKey)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let node = draggedNode else { return }
        guard !isGrid else {
            // 그리드: 임계값 넘으면 탭 취소만
            if hypot(touch.location(in: self).x - dragStartPoint.x,
                     touch.location(in: self).y - dragStartPoint.y) > dragThreshold { dragMoved = true }
            return
        }
        let location = touch.location(in: self)

        if hypot(location.x - dragStartPoint.x, location.y - dragStartPoint.y) > dragThreshold {
            dragMoved = true
            cancelLongPress()
        }

        let now = CACurrentMediaTime()
        let dt = max(now - lastDragTime, 1.0 / 120.0)
        dragVelocity = CGVector(dx: (location.x - lastDragPoint.x) / CGFloat(dt),
                                dy: (location.y - lastDragPoint.y) / CGFloat(dt))
        node.position = location
        lastDragPoint = location
        lastDragTime = now

        // 스티커 드래그 중: 폴더 하이라이트 + (폴더 안이면) 뒤로가기 영역 하이라이트.
        if catchId(node) != nil {
            updateFolderHighlight(under: node)
            if ejectEnabled { setEjectHover(inEjectZone(node.position)) }
        }
    }

    private func updateFolderHighlight(under node: SKNode) {
        let target = folderNode(near: node)
        guard target !== hoveredFolder else { return }
        hoveredFolder?.run(.scale(to: 1.0, duration: 0.12))
        hoveredFolder = target
        target?.run(.scale(to: 1.18, duration: 0.12))
    }

    private func clearFolderHighlight() {
        hoveredFolder?.run(.scale(to: 1.0, duration: 0.12))
        hoveredFolder = nil
    }

    private func setEjectHover(_ on: Bool) {
        guard on != ejectHovered else { return }
        ejectHovered = on
        onEjectHover?(on)
    }

    /// 스티커를 폴더 밖으로 빼는 연출(좌상단으로 빨려 나가며 사라짐).
    private func ejectSticker(_ node: SKSpriteNode, sticker sid: UUID) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        setEjectHover(false)
        onEjectSticker?(sid)
        node.physicsBody = nil
        let target = CGPoint(x: 36, y: size.height - 36)
        node.run(.sequence([
            .group([.move(to: target, duration: 0.25),
                    .scale(to: 0.08, duration: 0.25),
                    .fadeOut(withDuration: 0.25)]),
            .removeFromParent()
        ]))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishDrag()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishDrag()
    }

    private func finishDrag() {
        cancelLongPress()
        guard let node = draggedNode else { return }
        draggedNode = nil

        let duration = CACurrentMediaTime() - dragStartTime
        let isTap = !dragMoved && duration < longPressDuration

        if isGrid {
            if isTap, let id = catchId(node) { onTapCatch?(id) }
            return
        }

        clearFolderHighlight()
        setEjectHover(false)
        onGrabChanged?(false)
        node.physicsBody?.collisionBitMask = 0xFFFFFFFF   // 충돌 복원(양방향)
        node.physicsBody?.categoryBitMask = 0xFFFFFFFF
        node.physicsBody?.isDynamic = true

        // 스티커를 폴더 근처에 드롭 → 그 폴더에 담기.
        if dragMoved, let sid = catchId(node),
           let folder = folderNode(near: node), let fid = folderId(folder) {
            dropIntoFolder(node, sticker: sid, folder: folder, folderId: fid)
            return
        }

        // 폴더 안: 스티커를 뒤로가기 영역에 드롭 → 폴더 밖(미분류)으로.
        if dragMoved, ejectEnabled, let sid = catchId(node), inEjectZone(node.position) {
            ejectSticker(node, sticker: sid)
            return
        }

        node.zPosition = 0   // z 복원(드롭이 아니면 다시 일반 레이어로)

        if dragMoved {
            node.physicsBody?.velocity = clampVelocity(dragVelocity, max: 1500)
        }

        if isTap {
            if let fid = folderId(node) { onOpenFolder?(fid) }
            else if let id = catchId(node) { onTapCatch?(id) }
        }
    }

    /// 드래그 중인 스티커에 가장 가까운(잡기 반경 내) 폴더 노드. 정확히 안 겹쳐도 잡힘.
    private func folderNode(near node: SKNode) -> SKNode? {
        let p = node.position
        var best: SKNode?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for child in children where child !== node && isFolder(child) {
            let d = hypot(child.position.x - p.x, child.position.y - p.y)
            let capture = (max(child.frame.width, child.frame.height)
                           + max(node.frame.width, node.frame.height)) / 2 * 0.85
            if d < capture && d < bestDist { best = child; bestDist = d }
        }
        return best
    }

    /// 스티커를 폴더로 빨려 들어가는 연출과 함께 담는다.
    private func dropIntoFolder(_ node: SKSpriteNode, sticker sid: UUID, folder: SKNode, folderId fid: UUID) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onDropOnFolder?(sid, fid)
        node.physicsBody = nil
        node.run(.sequence([
            .group([.move(to: folder.position, duration: 0.28),
                    .scale(to: 0.08, duration: 0.28),
                    .fadeOut(withDuration: 0.28)]),
            .removeFromParent()
        ]))
        folder.run(.sequence([.scale(to: 1.15, duration: 0.1), .scale(to: 1.0, duration: 0.12)]))
    }

    /// 길게 누르면 즉시 삭제하지 않고 삭제를 요청한다(호스트가 확인 다이얼로그 표시).
    private func requestDelete(_ node: SKSpriteNode) {
        // 드래그로 전환됐으면 무시.
        guard draggedNode === node, !dragMoved else { return }
        onGrabChanged?(false)
        node.physicsBody?.collisionBitMask = 0xFFFFFFFF   // 충돌 복원(취소 대비)
        node.physicsBody?.categoryBitMask = 0xFFFFFFFF
        node.physicsBody?.isDynamic = true
        node.zPosition = 0
        draggedNode = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let name = node.name, let id = UUID(uuidString: name) {
            onRequestDelete?(id)
        }
    }

    /// 폴더 길게 누름 → 편집 요청(이동/탭과 구분).
    private func requestEditFolder(_ node: SKSpriteNode) {
        guard draggedNode === node, !dragMoved else { return }
        onGrabChanged?(false)
        node.physicsBody?.collisionBitMask = 0xFFFFFFFF
        node.physicsBody?.categoryBitMask = 0xFFFFFFFF
        node.physicsBody?.isDynamic = true
        node.zPosition = 0
        draggedNode = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if let id = folderId(node) { onEditFolder?(id) }
    }

    /// 삭제 확정 시: 흔들고 사라지는 연출과 함께 노드 제거.
    func vanish(id: UUID) {
        guard let node = childNode(withName: id.uuidString) as? SKSpriteNode else { return }
        node.physicsBody = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let wiggle = SKAction.sequence([
            .rotate(byAngle: 0.25, duration: 0.05),
            .rotate(byAngle: -0.5, duration: 0.1),
            .rotate(byAngle: 0.25, duration: 0.05)
        ])
        let vanish = SKAction.group([.fadeOut(withDuration: 0.2), .scale(to: 0.1, duration: 0.2)])
        node.run(.sequence([wiggle, vanish, .removeFromParent()]))
    }

    private func clampVelocity(_ v: CGVector, max maxMagnitude: CGFloat) -> CGVector {
        let magnitude = hypot(v.dx, v.dy)
        guard magnitude > maxMagnitude, magnitude > 0 else { return v }
        let ratio = maxMagnitude / magnitude
        return CGVector(dx: v.dx * ratio, dy: v.dy * ratio)
    }
}
