/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the AR experience.
*/

import UIKit
import SceneKit
import ARKit

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {

    enum SessionState {
        case adjustingBoard
        case placingBoard
    }

    var sessionState = SessionState.placingBoard

    var gameBoard = GameBoard()
    var panOffset = float3()

    // MARK: - IBOutlets

    @IBOutlet weak var sessionInfoView: UIView!
    @IBOutlet weak var sessionInfoLabel: UILabel!
    @IBOutlet weak var sceneView: ARSCNView!

    // MARK: - View Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        let recognizers: [UIGestureRecognizer] = [
            UITapGestureRecognizer(target: self, action: #selector(handleTap(recognizer:))),
            UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(recognizer:))),
            UIPanGestureRecognizer(target: self, action: #selector(handlePan(recognizer:))),
            UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(recognizer:)))
        ]

        recognizers.forEach {
            $0.delegate = self
            sceneView.addGestureRecognizer($0)
        }
    }

    /// - Tag: StartARSession
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Start the view's AR session with a configuration that uses the rear camera,
        // device position and orientation tracking, and plane detection.
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        sceneView.session.run(configuration)

        // Set a delegate to track the number of plane anchors for providing UI feedback.
        sceneView.session.delegate = self
        
        // Prevent the screen from being dimmed after a while as users will likely
        // have long periods of interaction without touching the screen or buttons.
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Show debug UI to view performance metrics (e.g. frames per second).
        sceneView.showsStatistics = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Pause the view's AR session.
        sceneView.session.pause()
    }

    // MARK: - ARSCNViewDelegate
    
    /// - Tag: PlaceARContent
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard anchor is ARPlaneAnchor else { return }

        gameBoard.removeFromParentNode()
        node.addChildNode(gameBoard)
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        guard let frame = session.currentFrame else { return }
        updateSessionInfoLabel(for: frame, trackingState: frame.camera.trackingState)
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let frame = session.currentFrame else { return }
        updateGameBoard(frame: frame)
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        guard let frame = session.currentFrame else { return }
        updateSessionInfoLabel(for: frame, trackingState: frame.camera.trackingState)
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        updateSessionInfoLabel(for: session.currentFrame!, trackingState: camera.trackingState)
    }

    // MARK: - ARSessionObserver

    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay.
        sessionInfoLabel.text = "Session was interrupted"
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required.
        sessionInfoLabel.text = "Session interruption ended"
        resetTracking()
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        sessionInfoLabel.text = "Session failed: \(error.localizedDescription)"
        guard error is ARError else { return }
        
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        // Remove optional error messages.
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        
        DispatchQueue.main.async {
            // Present an alert informing about the error that has occurred.
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
                self.resetTracking()
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }

    // MARK: - Private methods

    private func updateSessionInfoLabel(for frame: ARFrame, trackingState: ARCamera.TrackingState) {
        // Update the UI to provide feedback on the state of the AR experience.
        let message: String

        switch trackingState {
        case .normal where frame.anchors.isEmpty:
            // No planes detected; provide instructions for this app's AR interactions.
            message = "Move the device around to detect horizontal and vertical surfaces."
            
        case .notAvailable:
            message = "Tracking unavailable."
            
        case .limited(.excessiveMotion):
            message = "Tracking limited - Move the device more slowly."
            
        case .limited(.insufficientFeatures):
            message = "Tracking limited - Point the device at an area with visible surface detail, or improve lighting conditions."
            
        case .limited(.initializing):
            message = "Initializing AR session."
            
        default:
            // No feedback needed when tracking is normal and planes are visible.
            // (Nor when in unreachable limited-tracking states.)
            message = ""

        }

        sessionInfoLabel.text = message
        sessionInfoView.isHidden = message.isEmpty
    }

    private func resetTracking() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
}

extension ViewController {

    var screenCenter: CGPoint {
        let bounds = sceneView.bounds
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func updateGameBoard(frame: ARFrame) {
        // Make sure this is only run on the render thread

        guard sessionState == .placingBoard else { return }

        if gameBoard.parent == nil {
            sceneView.scene.rootNode.addChildNode(gameBoard)
        }

        if case .normal = frame.camera.trackingState {

            if let result = sceneView.hitTest(screenCenter, types: [.estimatedHorizontalPlane, .existingPlaneUsingExtent]).first {
                // Ignore results that are too close to the camera when initially placing
                guard result.distance > 0.5 else { return }

                gameBoard.update(with: result, camera: frame.camera)
            }
        }
    }

}


extension ViewController: UIGestureRecognizerDelegate {
    @objc func handleTap(recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        sessionState = (sessionState == .adjustingBoard) ? .placingBoard : .adjustingBoard
    }

    @objc func handlePan(recognizer: UIPanGestureRecognizer) {
        sessionState = .adjustingBoard

        let location = recognizer.location(in: sceneView)
        let results = sceneView.hitTest(location, types: .existingPlane)
        guard let nearestPlane = results.first else {
            return
        }

        switch recognizer.state {
        case .began:
            panOffset = nearestPlane.worldTransform.columns.3.xyz - gameBoard.simdWorldPosition
        case .changed:
            gameBoard.simdWorldPosition = nearestPlane.worldTransform.columns.3.xyz - panOffset
        default:
            break
        }
    }

    @objc func handlePinch(recognizer: UIPinchGestureRecognizer) {
        sessionState = .adjustingBoard

        switch recognizer.state {
        case .changed:
            gameBoard.scale(by: Float(recognizer.scale))
            recognizer.scale = 1
        default:
            break
        }
    }

    @objc func handleRotation(recognizer: UIRotationGestureRecognizer) {
        sessionState = .adjustingBoard

        switch recognizer.state {
        case .changed:
            if gameBoard.eulerAngles.x > .pi / 2 {
                gameBoard.simdEulerAngles.y += Float(recognizer.rotation)
            } else {
                gameBoard.simdEulerAngles.y -= Float(recognizer.rotation)
            }
            recognizer.rotation = 0
        default:
            break
        }
    }

    func gestureRecognizer(_ first: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith second: UIGestureRecognizer) -> Bool {
        if first is UIRotationGestureRecognizer && second is UIPinchGestureRecognizer {
            return true
        } else if first is UIRotationGestureRecognizer && second is UIPanGestureRecognizer {
            return true
        } else if first is UIPinchGestureRecognizer && second is UIRotationGestureRecognizer {
            return true
        } else if first is UIPinchGestureRecognizer && second is UIPanGestureRecognizer {
            return true
        } else if first is UIPanGestureRecognizer && second is UIPinchGestureRecognizer {
            return true
        } else if first is UIPanGestureRecognizer && second is UIRotationGestureRecognizer {
            return true
        }
        return false
    }

}
