//
//  ViewController.swift
//  AnimatedImageIOS
//
//  Created by vitalii on 27.10.2020.
//  Copyright © 2020 Vitalii. All rights reserved.
//

import UIKit
import AVFoundation
import AVKit
import Photos

class ViewController: UIViewController {
	var videoURL: URL!
	private var player: AVPlayer!
	private var playerLayer: AVPlayerLayer!
	private let editor = VideoEditor()
	
	@IBOutlet weak var btSave: UIButton!
	@IBOutlet weak var videoView: UIView!
	@IBOutlet weak var activityIndicator: UIActivityIndicatorView!
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		navigationController?.setNavigationBarHidden(false, animated: animated)
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		// Do any additional setup after loading the view.
		showInProgress()
		
		
		videoURL = editor.videoFileLocation(filename: "animatedImage") as URL

		if let image = UIImage(named: "soccerball") {
			VideoEditor.writeSingleImageToMovie(image: image, movieLength: 5.0, outputFileURL: videoURL) { [weak self] (error) in
				if let error = error{
					print(error)
				}
				else{
					self!.editor.addAnimationOverlay(fromVideoAt: (self?.videoURL)!, withOverlayText: "Animated\ntext") { [weak self] exportedURL in
						self?.showCompleted()
						guard let exportedURL = exportedURL else {
							return
						}
						
						self?.videoURL = exportedURL
						self?.player = AVPlayer(url: exportedURL)
						self?.playerLayer = AVPlayerLayer(player: self?.player)
						self?.playerLayer.frame = self?.videoView.bounds as! CGRect
						self?.videoView.layer.addSublayer((self?.playerLayer)!)
						self?.player.play()
						NotificationCenter.default.addObserver(
							forName: .AVPlayerItemDidPlayToEndTime,
							object: nil,
							queue: nil) { [weak self] _ in self?.restart() }
						
						
					}
				}
				
			}
		}
		
	}
	
	deinit {
		NotificationCenter.default.removeObserver(
			self,
			name: .AVPlayerItemDidPlayToEndTime,
			object: nil)
	}
	
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
	}
	
	private func restart() {
		player.seek(to: .zero)
		player.play()
	}
	
	@IBAction func saveVideoButtonTapped(_ sender: Any) {
		PHPhotoLibrary.requestAuthorization { [weak self] status in
			switch status {
			case .authorized:
				self?.saveVideoToPhotos()
			default:
				print("Photos permissions not granted.")
				return
			}
		}
	}
	
	private func showInProgress() {
		activityIndicator.startAnimating()
		btSave.isEnabled = false
	}
	
	private func showCompleted() {
		activityIndicator.stopAnimating()
		btSave.isEnabled = true
	}
	
	private func saveVideoToPhotos() {
		PHPhotoLibrary.shared().performChanges( {
			PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: self.videoURL)
		}) { [weak self] (isSaved, error) in
			if isSaved {
				print("Video saved.")
			} else {
				print("Cannot save video.")
				print(error ?? "unknown error")
			}
			DispatchQueue.main.async {
				self?.navigationController?.popViewController(animated: true)
			}
		}
	}
}

