import SpriteKit
import UIKit

/// 팔로잉 서클 이미지 — 아바타가 있으면 원형+흰 링, 없으면 그레이프 원 + 이니셜.
func personCircleImage(avatar: UIImage?, initial: String, size: CGFloat = 220) -> UIImage {
    if let avatar { return avatar.circularRinged(size: size, ring: size * 0.05) }
    let fmt = UIGraphicsImageRendererFormat.default()
    fmt.opaque = false; fmt.scale = 2
    return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: fmt).image { _ in
        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: size, height: size)).fill()
        let ring = size * 0.05
        let inner = CGRect(x: ring, y: ring, width: size - ring * 2, height: size - ring * 2)
        UIColor(hex: 0xC4B0FF).setFill()
        UIBezierPath(ovalIn: inner).fill()
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let ch = String((initial.trimmingCharacters(in: .whitespaces).first ?? "?")).uppercased()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size * 0.42, weight: .heavy),
            .foregroundColor: UIColor.white, .paragraphStyle: para
        ]
        let h = size * 0.5
        (ch as NSString).draw(in: CGRect(x: 0, y: size / 2 - h / 2, width: size, height: h), withAttributes: attrs)
    }
}

/// 팔로잉한 사람들의 원형 아바타가 중력으로 쌓이는 물리 씬(항아리뷰 축소판).
/// 중력 ↔ 그리드 정렬 토글, 탭하면 해당 유저 프로필.
final class FollowScene: SKScene {
    private let motion = MotionService()
    var onTapPerson: ((UUID) -> Void)?
    /// 하단 떠있는 탭바와 충돌하도록 막는 보이지 않는 배리어(서클이 바 뒤로 숨지 않게).
    var toolbarBarrier: (width: CGFloat, height: CGFloat, bottomMargin: CGFloat)? {
        didSet { rebuildToolbarBarrier() }
    }
    private var barrierNode: SKNode?

    private let displayDiameter: CGFloat = 132   // 스티커 폴더 동그라미(StickerScene maxDim 132)와 동일 크기
    private(set) var isGrid = false
    private var lastGravity = CGVector(dx: 0, dy: -9.8)

    private var draggedNode: SKSpriteNode?
    private var dragStart: CGPoint = .zero
    private var dragMoved = false

    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = 120
        backgroundColor = .clear
        scaleMode = .resizeFill
        anchorPoint = .zero
        rebuildWalls()
        rebuildToolbarBarrier()
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
        motion.onGravity = { [weak self] v in
            DispatchQueue.main.async {
                guard let self, !self.isGrid else { return }
                if abs(v.dx - self.lastGravity.dx) + abs(v.dy - self.lastGravity.dy) > 0.3 {
                    self.physicsWorld.gravity = v; self.lastGravity = v
                }
            }
        }
        motion.start()
    }

    deinit { motion.stop() }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize); rebuildWalls(); rebuildToolbarBarrier()
    }

    private func rebuildWalls() {
        guard size.width > 1, size.height > 1 else { physicsBody = nil; return }
        let body = SKPhysicsBody(edgeLoopFrom: CGRect(origin: .zero, size: size))
        body.friction = 0.4
        physicsBody = body
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

    override func update(_ currentTime: TimeInterval) {
        for case let n as SKSpriteNode in children {
            guard let b = n.physicsBody, n !== draggedNode else { continue }
            if abs(b.angularVelocity) > 4 { b.angularVelocity = b.angularVelocity < 0 ? -4 : 4 }
            let v = b.velocity, s = hypot(v.dx, v.dy)
            if s > 1400 { b.velocity = CGVector(dx: v.dx * 1400 / s, dy: v.dy * 1400 / s) }
        }
    }

    // MARK: - Spawn

    func clearAll() {
        for case let n as SKSpriteNode in children where n.physicsBody != nil { n.removeFromParent() }
        draggedNode = nil
    }

    func addPerson(id: UUID, image: UIImage) {
        let node = SKSpriteNode(texture: SKTexture(image: image))
        node.name = id.uuidString
        node.size = CGSize(width: displayDiameter, height: displayDiameter)
        let body = SKPhysicsBody(circleOfRadius: displayDiameter * 0.48)
        body.restitution = 0.04; body.friction = 0.5
        body.linearDamping = 0.25; body.angularDamping = 0.7
        body.usesPreciseCollisionDetection = true
        node.physicsBody = body
        let half = displayDiameter / 2
        node.position = CGPoint(x: .random(in: half...max(half, size.width - half)),
                                y: size.height - displayDiameter)
        addChild(node)
    }

    // MARK: - Grid / gravity

    private var personNodes: [SKSpriteNode] {
        children.compactMap { $0 as? SKSpriteNode }.filter { $0.physicsBody != nil }
    }

    func arrangeGrid() {
        isGrid = true
        let nodes = personNodes
        guard !nodes.isEmpty, size.width > 1 else { return }
        let cols = max(3, min(5, Int(size.width / 96)))
        let cell = size.width / CGFloat(cols)
        let startX = cell / 2
        let startY = size.height - deviceSafeAreaTop - 60
        for (i, n) in nodes.enumerated() {
            n.physicsBody?.isDynamic = false
            n.physicsBody?.velocity = .zero
            let c = i % cols, r = i / cols
            let action = SKAction.group([
                .move(to: CGPoint(x: startX + CGFloat(c) * cell, y: startY - CGFloat(r) * cell), duration: 0.4),
                .scale(to: (cell * 0.82) / displayDiameter, duration: 0.4)
            ])
            action.timingMode = .easeInEaseOut
            n.run(action)
        }
    }

    func releaseGrid() {
        isGrid = false
        for n in personNodes {
            n.run(.scale(to: 1, duration: 0.25))
            n.physicsBody?.isDynamic = true
            n.physicsBody?.applyImpulse(CGVector(dx: .random(in: -20...20), dy: .random(in: -10...20)))
        }
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let loc = t.location(in: self)
        guard let n = nodes(at: loc).first(where: { $0.physicsBody != nil }) as? SKSpriteNode else { return }
        draggedNode = n; dragStart = loc; dragMoved = false
        if !isGrid { n.physicsBody?.isDynamic = false }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let n = draggedNode else { return }
        let loc = t.location(in: self)
        if hypot(loc.x - dragStart.x, loc.y - dragStart.y) > 12 { dragMoved = true }
        if !isGrid { n.position = loc }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish() }

    private func finish() {
        guard let n = draggedNode else { return }
        draggedNode = nil
        if !isGrid { n.physicsBody?.isDynamic = true }
        if !dragMoved, let name = n.name, let id = UUID(uuidString: name) { onTapPerson?(id) }
    }
}
