import SpriteKit
import UIKit

/// 스티커들이 구슬처럼 중력으로 쌓이는 물리 씬.
/// - 실루엣 외곽 충돌(SKPhysicsBody(texture:))
/// - 자이로 중력 / 흔들기 섞임 / 드래그·던지기 / 길게 눌러 삭제
final class StickerScene: SKScene {
    private let motion = MotionService()

    /// 스티커를 잡았는지(true)/놓았는지(false) 알린다.
    var onGrabChanged: ((Bool) -> Void)?
    /// 길게 눌러 삭제가 확정되면 해당 캐치 id를 알린다(호스트가 서버 삭제).
    var onDeleteCatch: ((UUID) -> Void)?

    private let displayMaxDimension: CGFloat = 140
    static let rimColor = UIColor(hex: 0xE3FB85)   // 테마 라임

    /// 하단 툴바(가운데 알약) 충돌 바디 — 스티커가 바에 가려지지 않게 부딪힘.
    /// (width, height, bottomMargin) — 씬 좌표 기준, 가로 중앙 정렬.
    var toolbarBarrier: (width: CGFloat, height: CGFloat, bottomMargin: CGFloat)? {
        didSet { rebuildToolbarBarrier() }
    }
    private var barrierNode: SKNode?

    /// 그리드 정렬 모드(중력 off, 터치 비활성).
    private(set) var isGrid = false

    // 드래그 상태
    private var draggedNode: SKSpriteNode?
    private var dragStartPoint: CGPoint = .zero
    private var lastDragPoint: CGPoint = .zero
    private var lastDragTime: TimeInterval = 0
    private var dragVelocity: CGVector = .zero
    private var dragMoved = false

    // 길게 눌러 삭제
    private var longPressTimer: Timer?
    private let longPressDuration: TimeInterval = 0.5
    private let dragThreshold: CGFloat = 12

    private var bgNode: SKSpriteNode?

    override func didMove(to view: SKView) {
        backgroundColor = Theme.sceneTop
        scaleMode = .resizeFill
        anchorPoint = .zero
        rebuildBackground()
        rebuildWalls()
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)

        motion.onGravity = { [weak self] vector in
            DispatchQueue.main.async { self?.physicsWorld.gravity = vector }
        }
        motion.onShake = { [weak self] in
            DispatchQueue.main.async { self?.shuffle() }
        }
        motion.start()
    }

    deinit { motion.stop() }

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
        // 바닥 + 좌우만 막고 위는 열어둔다(위에서 떨어지는 스티커가 들어올 수 있도록).
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: size.width, y: 0))
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        let body = SKPhysicsBody(edgeChainFrom: path)
        body.friction = 0.4
        physicsBody = body
    }

    // MARK: - Spawning

    /// 캐치 1개를 물리 항아리에 투하한다(이미지는 호스트가 로드해 전달).
    func addCatch(id: UUID, display: UIImage, body: UIImage) {
        addStickerNode(displayImage: display, bodyImage: body, id: id)
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
        longPressTimer?.invalidate()
        longPressTimer = nil
    }

    private func addStickerNode(displayImage: UIImage, bodyImage: UIImage, id: UUID) {
        // 누끼 둘레에 테마색(라임) 스티커 테두리.
        let working = displayImage.resized(maxDimension: 420)
        let borderW = max(working.size.width, working.size.height) * 0.045
        let bordered = working.stickerBordered(color: StickerScene.rimColor, width: borderW)

        let texture = SKTexture(image: bordered)
        let node = SKSpriteNode(texture: texture)
        node.name = id.uuidString

        // 표시 크기 정규화: 긴 변을 displayMaxDimension 이하로.
        let longest = max(bordered.size.width, bordered.size.height)
        let scale = longest > 0 ? min(1, displayMaxDimension / longest) : 1
        let displaySize = CGSize(width: max(1, bordered.size.width * scale),
                                 height: max(1, bordered.size.height * scale))
        node.size = displaySize

        // 물리 바디는 테두리를 뺀 내부 실루엣 기준.
        let innerW = bordered.size.width > 0 ? working.size.width / bordered.size.width : 1
        let innerH = bordered.size.height > 0 ? working.size.height / bordered.size.height : 1
        let bodySize = CGSize(width: displaySize.width * innerW, height: displaySize.height * innerH)
        let bodyTexture = SKTexture(image: bodyImage)
        let body = SKPhysicsBody(texture: bodyTexture, alphaThreshold: 0.5, size: bodySize)
        body.restitution = 0.1
        body.friction = 0.4
        body.allowsRotation = true
        body.isDynamic = true
        node.physicsBody = body

        // 상단 랜덤 위치에서 낙하.
        let half = displaySize.width / 2
        let minX = half
        let maxX = max(half, size.width - half)
        node.position = CGPoint(x: .random(in: minX...maxX), y: size.height + displaySize.height)
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
        guard !isGrid else { return }   // 그리드 모드에선 터치 비활성
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        guard let node = nodes(at: location).first(where: { $0.physicsBody != nil }) as? SKSpriteNode else { return }

        draggedNode = node
        dragStartPoint = location
        lastDragPoint = location
        lastDragTime = CACurrentMediaTime()
        dragVelocity = .zero
        dragMoved = false
        node.physicsBody?.isDynamic = false   // 드래그 중 물리 분리(desync 방지)
        onGrabChanged?(true)                  // 잡는 동안 페이지 스크롤 잠금

        longPressTimer?.invalidate()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDuration, repeats: false) { [weak self, weak node] _ in
            guard let self, let node else { return }
            self.confirmDelete(node)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let node = draggedNode else { return }
        let location = touch.location(in: self)

        if hypot(location.x - dragStartPoint.x, location.y - dragStartPoint.y) > dragThreshold {
            dragMoved = true
            longPressTimer?.invalidate()
            longPressTimer = nil
        }

        let now = CACurrentMediaTime()
        let dt = max(now - lastDragTime, 1.0 / 120.0)
        dragVelocity = CGVector(dx: (location.x - lastDragPoint.x) / CGFloat(dt),
                                dy: (location.y - lastDragPoint.y) / CGFloat(dt))
        node.position = location
        lastDragPoint = location
        lastDragTime = now
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishDrag()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishDrag()
    }

    private func finishDrag() {
        longPressTimer?.invalidate()
        longPressTimer = nil
        defer { onGrabChanged?(false) }
        guard let node = draggedNode else { return }
        node.physicsBody?.isDynamic = true
        if dragMoved {
            node.physicsBody?.velocity = clampVelocity(dragVelocity, max: 1500)
        }
        draggedNode = nil
    }

    private func confirmDelete(_ node: SKSpriteNode) {
        // 드래그로 전환됐으면 삭제하지 않는다.
        guard draggedNode === node, !dragMoved else { return }
        onGrabChanged?(false)

        if let name = node.name, let id = UUID(uuidString: name) {
            onDeleteCatch?(id)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        node.physicsBody = nil
        let wiggle = SKAction.sequence([
            .rotate(byAngle: 0.25, duration: 0.05),
            .rotate(byAngle: -0.5, duration: 0.1),
            .rotate(byAngle: 0.25, duration: 0.05)
        ])
        let vanish = SKAction.group([.fadeOut(withDuration: 0.2), .scale(to: 0.1, duration: 0.2)])
        node.run(.sequence([wiggle, vanish, .removeFromParent()]))
        draggedNode = nil
    }

    private func clampVelocity(_ v: CGVector, max maxMagnitude: CGFloat) -> CGVector {
        let magnitude = hypot(v.dx, v.dy)
        guard magnitude > maxMagnitude, magnitude > 0 else { return v }
        let ratio = maxMagnitude / magnitude
        return CGVector(dx: v.dx * ratio, dy: v.dy * ratio)
    }
}
