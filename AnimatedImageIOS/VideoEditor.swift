//
//  VideoEditor.swift
//  AnimatedImageIOS
//
//  Created by vitalii on 27.10.2020.
//  Copyright © 2020 Vitalii. All rights reserved.
//

import UIKit
import AVFoundation

class VideoEditor {
	
	static func pixelBuffer(fromImage image: CGImage, size: CGSize) throws -> CVPixelBuffer {
		let options: CFDictionary = [kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true] as CFDictionary
		var pxbuffer: CVPixelBuffer? = nil
		let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, options, &pxbuffer)
		guard let buffer = pxbuffer, status == kCVReturnSuccess else { throw NSError(domain: "SomeErrorDomain", code: -2001 /* some error code */, userInfo: ["description": "Can't make pixelBuffer"]) }
		
		CVPixelBufferLockBaseAddress(buffer, [])
		guard let pxdata = CVPixelBufferGetBaseAddress(buffer) else { throw NSError(domain: "SomeErrorDomain", code: -2001 /* some error code */, userInfo: ["description": "Can't make pixelBuffer"])  }
		let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
		
		let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
		guard let context = CGContext(data: pxdata, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { throw NSError(domain: "SomeErrorDomain", code: -2001 /* some error code */, userInfo: ["description": "Can't make pixelBuffer"])  }
		context.concatenate(CGAffineTransform(rotationAngle: 0))
		context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
		
		CVPixelBufferUnlockBaseAddress(buffer, [])
		
		return buffer
	}
	
	func videoFileLocation(filename: String) -> URL {
		let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
		let videoOutputUrl = URL(fileURLWithPath: documentsPath.appendingPathComponent(filename)).appendingPathExtension("mov")
		do {
			if FileManager.default.fileExists(atPath: videoOutputUrl.path) {
				try FileManager.default.removeItem(at: videoOutputUrl)
				print("file removed")
			}
		} catch {
			print(error)
		}
		
		return videoOutputUrl
	}
	
	static func writeSingleImageToMovie(image: UIImage, movieLength: TimeInterval, outputFileURL: URL, completion: @escaping (Error?) -> ()) {
		do {
			let imageSize = image.size
			let videoWriter = try AVAssetWriter(outputURL: outputFileURL, fileType: AVFileType.mov)
			let videoSettings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
												AVVideoWidthKey: imageSize.width,
												AVVideoHeightKey: imageSize.height]
			let videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
			let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoWriterInput, sourcePixelBufferAttributes: nil)
			
			if !videoWriter.canAdd(videoWriterInput) { throw NSError(domain: "SomeErrorDomain", code: -2001 /* some error code */, userInfo: ["description": "Can't write video"])  }
			videoWriterInput.expectsMediaDataInRealTime = true
			videoWriter.add(videoWriterInput)
			
			videoWriter.startWriting()
			let timeScale: Int32 = 600 // recommended in CMTime for movies.
			let halfMovieLength = Float64(movieLength/2.0) // videoWriter assumes frame lengths are equal.
			let startFrameTime = CMTimeMake(value: 0, timescale: timeScale)
			let endFrameTime = CMTimeMakeWithSeconds(halfMovieLength, preferredTimescale: timeScale)
			videoWriter.startSession(atSourceTime: startFrameTime)
			
			guard let cgImage = image.cgImage else { throw NSError(domain: "SomeErrorDomain", code: -2001 /* some error code */, userInfo: ["description": "Can't init cgImage"]) }
			let buffer: CVPixelBuffer = try self.pixelBuffer(fromImage: cgImage, size: imageSize)
			while !adaptor.assetWriterInput.isReadyForMoreMediaData { usleep(10) }
			adaptor.append(buffer, withPresentationTime: startFrameTime)
			while !adaptor.assetWriterInput.isReadyForMoreMediaData { usleep(10) }
			adaptor.append(buffer, withPresentationTime: endFrameTime)
			
			videoWriterInput.markAsFinished()
			videoWriter.finishWriting {
				completion(videoWriter.error)
			}
		} catch {
			completion(error)
		}
	}
	
	func addAnimationOverlay(fromVideoAt videoURL: URL, withOverlayText text: String, onComplete: @escaping (URL?) -> Void) {
		print(videoURL)
		let asset = AVURLAsset(url: videoURL)
		let composition = AVMutableComposition()
		
		guard
			let compositionTrack = composition.addMutableTrack(
				withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
			let assetTrack = asset.tracks(withMediaType: .video).first
			else {
				print("Something is wrong with the asset.")
				onComplete(nil)
				return
		}
		
		do {
			let timeRange = CMTimeRange(start: .zero, duration: asset.duration)
			try compositionTrack.insertTimeRange(timeRange, of: assetTrack, at: .zero)
			
			if let audioAssetTrack = asset.tracks(withMediaType: .audio).first,
				let compositionAudioTrack = composition.addMutableTrack(
					withMediaType: .audio,
					preferredTrackID: kCMPersistentTrackID_Invalid) {
				try compositionAudioTrack.insertTimeRange(
					timeRange,
					of: audioAssetTrack,
					at: .zero)
			}
		} catch {
			print(error)
			onComplete(nil)
			return
		}
		
		compositionTrack.preferredTransform = assetTrack.preferredTransform
		let videoInfo = orientation(from: assetTrack.preferredTransform)
		
		let videoSize: CGSize
		if videoInfo.isPortrait {
			videoSize = CGSize(
				width: assetTrack.naturalSize.height,
				height: assetTrack.naturalSize.width)
		} else {
			videoSize = assetTrack.naturalSize
		}

		let videoLayer = CALayer()
		videoLayer.frame = CGRect(origin: .zero, size: videoSize)
		let overlayLayer = CALayer()
		overlayLayer.frame = CGRect(origin: .zero, size: videoSize)

		
		addConfetti(to: overlayLayer)

		
		add(
			text: text,
			to: overlayLayer,
			videoSize: videoSize)
		
		let outputLayer = CALayer()
		outputLayer.frame = CGRect(origin: .zero, size: videoSize)

		outputLayer.addSublayer(videoLayer)
		outputLayer.addSublayer(overlayLayer)
		
		let videoComposition = AVMutableVideoComposition()
		videoComposition.renderSize = videoSize
		videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
		videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
			postProcessingAsVideoLayer: videoLayer,
			in: outputLayer)
		
		let instruction = AVMutableVideoCompositionInstruction()
		instruction.timeRange = CMTimeRange(
			start: .zero,
			duration: composition.duration)
		videoComposition.instructions = [instruction]
		let layerInstruction = compositionLayerInstruction(
			for: compositionTrack,
			assetTrack: assetTrack)
		instruction.layerInstructions = [layerInstruction]
		
		guard let export = AVAssetExportSession(
			asset: composition,
			presetName: AVAssetExportPresetHighestQuality)
			else {
				print("Cannot create export session.")
				onComplete(nil)
				return
		}
		
		let videoName = UUID().uuidString
		let exportURL = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent(videoName)
			.appendingPathExtension("mov")
		
		export.videoComposition = videoComposition
		export.outputFileType = .mov
		export.outputURL = exportURL
		
		export.exportAsynchronously {
			DispatchQueue.main.async {
				switch export.status {
				case .completed:
					onComplete(exportURL)
				default:
					print("Something went wrong during export.")
					print(export.error ?? "unknown error")
					onComplete(nil)
					break
				}
			}
		}
	}

	
	private func add(text: String, to layer: CALayer, videoSize: CGSize) {
		let attributedText = NSAttributedString(
			string: text,
			attributes: [
				.font: UIFont(name: "ArialRoundedMTBold", size: 60) as Any,
				.foregroundColor: UIColor(named: "greenColor")!,
				.strokeColor: UIColor.white,
				.strokeWidth: -3])
		
		let textLayer = CATextLayer()
		textLayer.string = attributedText
		textLayer.shouldRasterize = true
		textLayer.rasterizationScale = UIScreen.main.scale
		textLayer.backgroundColor = UIColor.clear.cgColor
		textLayer.alignmentMode = .center
		
		textLayer.frame = CGRect(
			x: 0,
			y: videoSize.height * 0.66,
			width: videoSize.width,
			height: 150)
		textLayer.displayIfNeeded()
		
		let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
		scaleAnimation.fromValue = 0.8
		scaleAnimation.toValue = 1.2
		scaleAnimation.duration = 0.5
		scaleAnimation.repeatCount = .greatestFiniteMagnitude
		scaleAnimation.autoreverses = true
		scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
		
		scaleAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
		scaleAnimation.isRemovedOnCompletion = false
		textLayer.add(scaleAnimation, forKey: "scale")
		
		layer.addSublayer(textLayer)
	}
	
	private func orientation(from transform: CGAffineTransform) -> (orientation: UIImage.Orientation, isPortrait: Bool) {
		var assetOrientation = UIImage.Orientation.up
		var isPortrait = false
		if transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0 {
			assetOrientation = .right
			isPortrait = true
		} else if transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0 {
			assetOrientation = .left
			isPortrait = true
		} else if transform.a == 1.0 && transform.b == 0 && transform.c == 0 && transform.d == 1.0 {
			assetOrientation = .up
		} else if transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0 {
			assetOrientation = .down
		}
		
		return (assetOrientation, isPortrait)
	}
	
	private func compositionLayerInstruction(for track: AVCompositionTrack, assetTrack: AVAssetTrack) -> AVMutableVideoCompositionLayerInstruction {
		let instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
		let transform = assetTrack.preferredTransform
		
		instruction.setTransform(transform, at: .zero)
		
		return instruction
	}
	
	private func addConfetti(to layer: CALayer) {
		let ranges = [
			0x1F601...0x1F64F
		]
		let images = ranges
			.flatMap { $0 }
			.compactMap { Unicode.Scalar($0) }
			.map(Character.init)
			.compactMap { String($0).textToImage() }

		let colors: [UIColor] = [.systemGreen, .systemRed, .systemBlue, .systemPink, .systemOrange, .systemPurple, .systemYellow]
		let cells: [CAEmitterCell] = (0...16).map { _ in
			let cell = CAEmitterCell()
			cell.contents = images.randomElement()?.cgImage
			cell.birthRate = 3
			cell.lifetime = 12
			cell.lifetimeRange = 0
			cell.velocity = CGFloat.random(in: 100...200)
			cell.velocityRange = 0
			cell.emissionLongitude = 0
			cell.emissionRange = 0.8
			cell.spin = 4

			cell.scale = CGFloat.random(in: 0.2...0.8)
			return cell
		}
		
		let emitter = CAEmitterLayer()
		emitter.emitterPosition = CGPoint(x: layer.frame.size.width / 2, y: layer.frame.size.height + 5)
		emitter.emitterShape = .line
		emitter.emitterSize = CGSize(width: layer.frame.size.width, height: 2)
		emitter.emitterCells = cells
		
		layer.addSublayer(emitter)
	}
}

extension String {
	func textToImage() -> UIImage? {
		let nsString = (self as NSString)
		let font = UIFont.systemFont(ofSize: 14) // you can change your font size here
		let stringAttributes = [NSAttributedString.Key.font: font]
		let imageSize = nsString.size(withAttributes: stringAttributes)
		
		UIGraphicsBeginImageContextWithOptions(imageSize, false, 0) //  begin image context
		UIColor.clear.set() // clear background
		UIRectFill(CGRect(origin: CGPoint(), size: imageSize)) // set rect size
		nsString.draw(at: CGPoint.zero, withAttributes: stringAttributes) // draw text within rect
		let image = UIGraphicsGetImageFromCurrentImageContext() // create image from context
		UIGraphicsEndImageContext() //  end image context
		
		return image ?? UIImage()
	}
}
