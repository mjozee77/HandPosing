/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The app's main view controller object.
*/

import UIKit
import AVFoundation
import Vision

class CameraViewController: UIViewController {

    private var cameraView: CameraView { view as! CameraView }
    
    private let videoDataOutputQueue = DispatchQueue(label: "CameraFeedDataOutput", qos: .userInteractive)
    private var cameraFeedSession: AVCaptureSession?
    private var handPoseRequest = VNDetectHumanHandPoseRequest()
    
    private let drawOverlay = CAShapeLayer()
    private let drawPath = UIBezierPath()
    private var evidenceBuffer = [HandGestureProcessor.PointsPair]()
    private var lastDrawPoint: CGPoint?
    private var isFirstSegment = true
    private var lastObservationTimestamp = Date()
    
    private var gestureProcessor = HandGestureProcessor()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        drawOverlay.frame = view.layer.bounds
        drawOverlay.lineWidth = 5
        drawOverlay.backgroundColor = #colorLiteral(red: 0.9999018312, green: 1, blue: 0.9998798966, alpha: 0.5).cgColor
        drawOverlay.strokeColor = #colorLiteral(red: 0.6, green: 0.1, blue: 0.3, alpha: 1).cgColor
        drawOverlay.fillColor = #colorLiteral(red: 0.9999018312, green: 1, blue: 0.9998798966, alpha: 0).cgColor
        drawOverlay.lineCap = .round
        view.layer.addSublayer(drawOverlay)
        // This sample app detects one hand only.
        handPoseRequest.maximumHandCount = 1
        // Add state change handler to hand gesture processor.
        gestureProcessor.didChangeStateClosure = { [weak self] state in
            self?.handleGestureStateChange(state: state)
        }
        // Add double tap gesture recognizer for clearing the draw path.
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleGesture(_:)))
        recognizer.numberOfTouchesRequired = 1
        recognizer.numberOfTapsRequired = 2
        view.addGestureRecognizer(recognizer)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        do {
            if cameraFeedSession == nil {
                cameraView.previewLayer.videoGravity = .resizeAspectFill
                try setupAVSession()
                cameraView.previewLayer.session = cameraFeedSession
            }
            cameraFeedSession?.startRunning()
        } catch {
            AppError.display(error, inViewController: self)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        cameraFeedSession?.stopRunning()
        super.viewWillDisappear(animated)
    }
    
    func setupAVSession() throws {
        // Select a front facing camera, make an input.
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw AppError.captureSessionSetup(reason: "Could not find a front facing camera.")
        }
        
        guard let deviceInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            throw AppError.captureSessionSetup(reason: "Could not create video device input.")
        }
        
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = AVCaptureSession.Preset.high
        
        // Add a video input.
        guard session.canAddInput(deviceInput) else {
            throw AppError.captureSessionSetup(reason: "Could not add video device input to the session")
        }
        session.addInput(deviceInput)
        
        let dataOutput = AVCaptureVideoDataOutput()
        if session.canAddOutput(dataOutput) {
            session.addOutput(dataOutput)
            // Add a video data output.
            dataOutput.alwaysDiscardsLateVideoFrames = true
            dataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
            dataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        } else {
            throw AppError.captureSessionSetup(reason: "Could not add video data output to the session")
        }
        session.commitConfiguration()
        cameraFeedSession = session
}
    
    func processPoints(thumbTip: CGPoint?, indexTip: CGPoint?, middleTip: CGPoint?, ringTip: CGPoint?, littleTip: CGPoint?, thumbIP: CGPoint?, thumbMP: CGPoint?, thumbCMC: CGPoint?, indexDIP: CGPoint?, indexPIP: CGPoint?, indexMCP: CGPoint?, middleDIP: CGPoint?, middlePIP: CGPoint?, middleMCP: CGPoint?, ringDIP: CGPoint?, ringPIP: CGPoint?, ringMCP: CGPoint?, littleDIP: CGPoint?, littlePIP: CGPoint?, littleMCP: CGPoint?, wrist: CGPoint?) {
        // Check that we have 21 points.
        guard let thumbPoint = thumbTip, let indexPoint = indexTip, let middlePoint = middleTip, let ringPoint = ringTip, let littlePoint = littleTip, let thumbIPPoint = thumbIP, let thumbMPPoint = thumbMP, let thumbCMCPoint = thumbCMC, let indexDIPPoint = indexDIP, let indexPIPPoint = indexPIP, let indexMCPPoint = indexMCP, let middleDIPPoint = middleDIP, let middlePIPPoint = middlePIP, let middleMCPPoint = middleMCP, let ringDIPPoint = ringDIP, let ringPIPPoint = ringPIP, let ringMCPPoint = ringMCP, let littleDIPPoint = littleDIP, let littlePIPPoint = littlePIP, let littleMCPPoint = littleMCP, let wristPoint = wrist else {
            // If there were no observations for more than 2 seconds reset gesture processor.
            if Date().timeIntervalSince(lastObservationTimestamp) > 2 {
                gestureProcessor.reset()
            }
            cameraView.showPoints([], color: .clear)
            return
        }
        
        // Convert points from AVFoundation coordinates to UIKit coordinates.
        let previewLayer = cameraView.previewLayer
        let thumbPointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: thumbPoint)
        let indexPointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: indexPoint)
        let middlePointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: middlePoint)
        let ringPointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: ringPoint)
        let littlePointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: littlePoint)
        let thumbIPPointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: thumbIPPoint)
        let thumbMPPointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: thumbMPPoint)
        let thumbCMCPointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: thumbCMCPoint)
        let indexDIPPointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: indexDIPPoint)
        let indexPIPPointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: indexPIPPoint)
        let indexMCPPointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: indexMCPPoint)
        let middleDIPPointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: middleDIPPoint)
        let middlePIPPointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: middlePIPPoint)
        let middleMCPPointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: middleMCPPoint)
        let ringDIPPointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: ringDIPPoint)
        let ringPIPPointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: ringPIPPoint)
        let ringMCPPointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: ringMCPPoint)
        let littleDIPPointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: littleDIPPoint)
        let littlePIPPointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: littlePIPPoint)
        let littleMCPPointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: littleMCPPoint)
        let wristPointConverted = previewLayer.layerPointConverted(fromCaptureDevicePoint: wristPoint)
        
        // Process new points
        gestureProcessor.processPointsPair((thumbPointConverted, indexPointConverted, middlePointConverted, ringPointConverted, littlePointConverted, thumbIPPointConverted, thumbMPPointConverted, thumbCMCPointConverted, indexDIPPointConverted, indexPIPPointConverted, indexMCPPointConverted, middleDIPPointConverted, middlePIPPointConverted, middleMCPPointConverted, ringDIPPointConverted, ringPIPPointConverted, ringMCPPointConverted, littleDIPPointConverted, littlePIPPointConverted, littleMCPPointConverted, wristPointConverted))
    }
    
    private func handleGestureStateChange(state: HandGestureProcessor.State) {
        let pointsPair = gestureProcessor.lastProcessedPointsPair
        var tipsColor: UIColor
        switch state {
        case .possiblePinch, .possibleApart:
            // We are in one of the "possible": states, meaning there is not enough evidence yet to determine
            // if we want to draw or not. For now, collect points in the evidence buffer, so we can add them
            // to a drawing path when required.
            evidenceBuffer.append(pointsPair)
            tipsColor = .orange
        case .pinched:
            // We have enough evidence to draw. Draw the points collected in the evidence buffer, if any.
            for bufferedPoints in evidenceBuffer {
                updatePath(with: bufferedPoints, isLastPointsPair: false)
            }
            // Clear the evidence buffer.
            evidenceBuffer.removeAll()
            // Finally, draw the current point.
            updatePath(with: pointsPair, isLastPointsPair: false)
            tipsColor = .green
        case .apart, .unknown:
            // We have enough evidence to not draw. Discard any evidence buffer points.
            evidenceBuffer.removeAll()
            // And draw the last segment of our draw path.
            updatePath(with: pointsPair, isLastPointsPair: true)
            tipsColor = .red
        }
        cameraView.showPoints([pointsPair.thumbTip, pointsPair.indexTip, pointsPair.middleTip, pointsPair.ringTip, pointsPair.littleTip, pointsPair.thumbIP, pointsPair.thumbMP, pointsPair.thumbCMC, pointsPair.indexDIP, pointsPair.indexPIP, pointsPair.indexMCP, pointsPair.middleDIP, pointsPair.middlePIP, pointsPair.middleMCP, pointsPair.ringDIP, pointsPair.ringPIP, pointsPair.ringMCP, pointsPair.littleDIP, pointsPair.littlePIP, pointsPair.littleMCP, pointsPair.wrist], color: tipsColor)
    }
    
    private func updatePath(with points: HandGestureProcessor.PointsPair, isLastPointsPair: Bool) {
        // Get the mid point between the tips.
        let (thumbTip, indexTip, middleTip, ringTip, littleTip, thumbIP, thumbMP, thumbCMC, indexDIP, indexPIP, indexMCP, middleDIP, middlePIP, middleMCP, ringDIP, ringPIP, ringMCP, littleDIP, littlePIP, littleMCP, wrist) = points
        let drawPoint = CGPoint.midPoint(p1: thumbTip, p2: indexTip)

        if isLastPointsPair {
            if let lastPoint = lastDrawPoint {
                // Add a straight line from the last midpoint to the end of the stroke.
               // drawPath.addLine(to: lastPoint)
            }
            // We are done drawing, so reset the last draw point.
            lastDrawPoint = nil
        } else {
            if lastDrawPoint == nil {
                // This is the beginning of the stroke.
                drawPath.move(to: drawPoint)
                isFirstSegment = true
            } else {
                let lastPoint = lastDrawPoint!
                // Get the midpoint between the last draw point and the new point.
                let midPoint = CGPoint.midPoint(p1: lastPoint, p2: drawPoint)
                if isFirstSegment {
                    // If it's the first segment of the stroke, draw a line to the midpoint.
                    //drawPath.addLine(to: midPoint)
                    isFirstSegment = false
                } else {
                    // Otherwise, draw a curve to a midpoint using the last draw point as a control point.
                    //drawPath.addQuadCurve(to: midPoint, controlPoint: lastPoint)
                }
            }
            // Remember the last draw point for the next update pass.
            lastDrawPoint = drawPoint
        }
        // Update the path on the overlay layer.
        drawOverlay.path = drawPath.cgPath
    }
    
    @IBAction func handleGesture(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else {
            return
        }
        evidenceBuffer.removeAll()
        drawPath.removeAllPoints()
        drawOverlay.path = drawPath.cgPath
    }
}

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        var thumbTip: CGPoint?
        var indexTip: CGPoint?
        var middleTip: CGPoint?
        var ringTip: CGPoint?
        var littleTip: CGPoint?
        var thumbIP: CGPoint?
        var thumbMP: CGPoint?
        var thumbCMC: CGPoint?
        var indexDIP: CGPoint?
        var indexPIP: CGPoint?
        var indexMCP: CGPoint?
        var middleDIP: CGPoint?
        var middlePIP: CGPoint?
        var middleMCP: CGPoint?
        var ringDIP: CGPoint?
        var ringPIP: CGPoint?
        var ringMCP: CGPoint?
        var littleDIP: CGPoint?
        var littlePIP: CGPoint?
        var littleMCP: CGPoint?
        var wrist: CGPoint?
        
        defer {
            DispatchQueue.main.sync {
                self.processPoints(thumbTip: thumbTip, indexTip: indexTip, middleTip: middleTip, ringTip: ringTip, littleTip: littleTip, thumbIP: thumbIP, thumbMP: thumbMP, thumbCMC: thumbCMC, indexDIP: indexDIP, indexPIP: indexPIP, indexMCP: indexMCP, middleDIP: middleDIP, middlePIP: middlePIP, middleMCP: middleMCP, ringDIP: ringDIP, ringPIP: ringPIP, ringMCP: ringMCP, littleDIP: littleDIP, littlePIP: littlePIP, littleMCP: littleMCP, wrist: wrist)
            }
        }

        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        do {
            // Perform VNDetectHumanHandPoseRequest
            try handler.perform([handPoseRequest])
            // Continue only when a hand was detected in the frame.
            // Since we set the maximumHandCount property of the request to 1, there will be at most one observation.
            guard let observation = handPoseRequest.results?.first else {
                return
            }
            // Get points for five fingers, all joints, and wrist.
            let thumbPoints = try observation.recognizedPoints(.thumb)
            let indexFingerPoints = try observation.recognizedPoints(.indexFinger)
            let middleFingerPoints = try observation.recognizedPoints(.middleFinger)
            let ringFingerPoints = try observation.recognizedPoints(.ringFinger)
            let littleFingerPoints = try observation.recognizedPoints(.littleFinger)
            let thumbIPPoints = try observation.recognizedPoints(.thumb)
            let thumbMPPoints = try observation.recognizedPoints(.thumb)
            let thumbCMCPoints = try observation.recognizedPoints(.thumb)
            let indexDIPPoints = try observation.recognizedPoints(.indexFinger)
            let indexPIPPoints = try observation.recognizedPoints(.indexFinger)
            let indexMCPPoints = try observation.recognizedPoints(.indexFinger)
            let middleDIPPoints = try observation.recognizedPoints(.middleFinger)
            let middlePIPPoints = try observation.recognizedPoints(.middleFinger)
            let middleMCPPoints = try observation.recognizedPoints(.middleFinger)
            let ringDIPPoints = try observation.recognizedPoints(.ringFinger)
            let ringPIPPoints = try observation.recognizedPoints(.ringFinger)
            let ringMCPPoints = try observation.recognizedPoints(.ringFinger)
            let littleDIPPoints = try observation.recognizedPoints(.littleFinger)
            let littlePIPPoints = try observation.recognizedPoints(.littleFinger)
            let littleMCPPoints = try observation.recognizedPoints(.littleFinger)
            let wristPoints = try observation.recognizedPoints(.all)
            
            // Look for tip points.
            guard let thumbTipPoint = thumbPoints[.thumbTip], let indexTipPoint = indexFingerPoints[.indexTip], let middleTipPoint = middleFingerPoints[.middleTip], let ringTipPoint = ringFingerPoints[.ringTip], let littleTipPoint = littleFingerPoints[.littleTip], let thumbIPPoint = thumbIPPoints[.thumbIP], let thumbMPPoint = thumbMPPoints[.thumbMP], let thumbCMCPoint = thumbCMCPoints[.thumbCMC], let indexDIPPoint = indexDIPPoints[.indexDIP], let indexPIPPoint = indexPIPPoints[.indexPIP], let indexMCPPoint = indexMCPPoints[.indexMCP], let middleDIPPoint = middleDIPPoints[.middleDIP], let middlePIPPoint = middlePIPPoints[.middlePIP], let middleMCPPoint = middleMCPPoints[.middleMCP], let ringDIPPoint = ringDIPPoints[.ringDIP], let ringPIPPoint = ringPIPPoints[.ringPIP], let ringMCPPoint = ringMCPPoints[.ringMCP], let littleDIPPoint = littleDIPPoints[.littleDIP], let littlePIPPoint = littlePIPPoints[.littlePIP], let littleMCPPoint = littleMCPPoints[.littleMCP], let wristPoint = wristPoints[.wrist]
            else {
                return
            }
            // Ignore low confidence points.
            guard thumbTipPoint.confidence > 0.3 && indexTipPoint.confidence > 0.3 && middleTipPoint.confidence > 0.3 && ringTipPoint.confidence > 0.3 && littleTipPoint.confidence > 0.3 && thumbIPPoint.confidence > 0.3 && thumbMPPoint.confidence > 0.3 && thumbCMCPoint.confidence > 0.3 && indexDIPPoint.confidence > 0.3 && indexPIPPoint.confidence > 0.3 && indexMCPPoint.confidence > 0.3 && middleDIPPoint.confidence > 0.3 && middlePIPPoint.confidence > 0.3 && middleMCPPoint.confidence > 0.3 && ringDIPPoint.confidence > 0.3 && ringPIPPoint.confidence > 0.3 && ringMCPPoint.confidence > 0.3 && littleDIPPoint.confidence > 0.3 && littlePIPPoint.confidence > 0.3 && littleMCPPoint.confidence > 0.3 && wristPoint.confidence > 0.3 else {
                return
            }
            // Convert points from Vision coordinates to AVFoundation coordinates.
            thumbTip = CGPoint(x: thumbTipPoint.location.x, y: 1 - thumbTipPoint.location.y)
            indexTip = CGPoint(x: indexTipPoint.location.x, y: 1 - indexTipPoint.location.y)
            middleTip = CGPoint(x: middleTipPoint.location.x, y: 1 - middleTipPoint.location.y)
            ringTip = CGPoint(x: ringTipPoint.location.x, y: 1 - ringTipPoint.location.y)
            littleTip = CGPoint(x: littleTipPoint.location.x, y: 1 - littleTipPoint.location.y)
            thumbIP = CGPoint(x: thumbIPPoint.location.x, y: 1 - thumbIPPoint.location.y)
            thumbMP = CGPoint(x: thumbMPPoint.location.x, y: 1 - thumbMPPoint.location.y)
            thumbCMC = CGPoint(x: thumbCMCPoint.location.x, y: 1 - thumbCMCPoint.location.y)
            indexDIP = CGPoint(x: indexDIPPoint.location.x, y: 1 - indexDIPPoint.location.y)
            indexPIP = CGPoint(x: indexPIPPoint.location.x, y: 1 - indexPIPPoint.location.y)
            indexMCP = CGPoint(x: indexMCPPoint.location.x, y: 1 - indexMCPPoint.location.y)
            middleDIP = CGPoint(x: middleDIPPoint.location.x, y: 1 - middleDIPPoint.location.y)
            middlePIP = CGPoint(x: middlePIPPoint.location.x, y: 1 - middlePIPPoint.location.y)
            middleMCP = CGPoint(x: middleMCPPoint.location.x, y: 1 - middleMCPPoint.location.y)
            ringDIP = CGPoint(x: ringDIPPoint.location.x, y: 1 - ringDIPPoint.location.y)
            ringPIP = CGPoint(x: ringPIPPoint.location.x, y: 1 - ringPIPPoint.location.y)
            ringMCP = CGPoint(x: ringMCPPoint.location.x, y: 1 - ringMCPPoint.location.y)
            littleDIP = CGPoint(x: littleDIPPoint.location.x, y: 1 - littleDIPPoint.location.y)
            littlePIP = CGPoint(x: littlePIPPoint.location.x, y: 1 - littlePIPPoint.location.y)
            littleMCP = CGPoint(x: littleMCPPoint.location.x, y: 1 - littleMCPPoint.location.y)
            wrist = CGPoint(x: wristPoint.location.x, y: 1 - wristPoint.location.y)
            
        } catch {
            cameraFeedSession?.stopRunning()
            let error = AppError.visionError(error: error)
            DispatchQueue.main.async {
                error.displayInViewController(self)
            }
        }
    }
}

