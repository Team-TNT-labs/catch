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

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(white: 0.06, alpha: 1)
        scaleMode = .resizeFill
        anchorPoint = .zero
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
        rebuildWalls()
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
        let texture = SKTexture(image: displayImage)
        let node = SKSpriteNode(texture: texture)
        node.name = id.uuidString

        // 표시 크기 정규화: 긴 변을 displayMaxDimension 이하로.
        let longest = max(displayImage.size.width, displayImage.size.height)
        let scale = longest > 0 ? min(1, displayMaxDimension / longest) : 1
        let displaySize = CGSize(width: max(1, displayImage.size.width * scale),
                                 height: max(1, displayImage.size.height * scale))
        node.size = displaySize

        // 실루엣 물리 바디(다운스케일 텍스처 기준, 표시 크기로 매핑).
        let bodyTexture = SKTexture(image: bodyImage)
        let body = SKPhysicsBody(texture: bodyTexture, alphaThreshold: 0.5, size: displaySize)
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
        for case let node as SKSpriteNode in children where node.physicsBody != nil {
            node.physicsBody?.applyImpulse(CGVector(dx: .random(in: -40...40), dy: .random(in: 20...90)))
            node.physicsBody?.applyAngularImpulse(.random(in: -0.05...0.05))
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
