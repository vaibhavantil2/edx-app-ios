//
//  TranscriptManager.swift
//  edX
//
//  Created by Salman on 29/03/2018.
//  Copyright © 2018 edX. All rights reserved.
//

import UIKit

protocol TranscriptManagerDelegate: AnyObject {
    func transcriptsLoaded(manager: TranscriptManager, transcripts: [TranscriptObject])
}

class TranscriptManager: NSObject {
    
    typealias Environment = OEXInterfaceProvider
    
    private let environment : Environment
    private let video: OEXHelperVideoDownload
    private let transcriptParser = TranscriptParser()
    private var transcripts: [TranscriptObject] = []
    weak var delegate: TranscriptManagerDelegate? {
        didSet {
            initializeSubtitle()
        }
    }
    
    init(environment: Environment, video: OEXHelperVideoDownload) {
        self.environment = environment
        self.video = video
        super.init()
    }
    
    private var captionURL: String {
        var url: String = ""
        let devicelangue = Locale.current.languageCode ?? ""

        if let ccSelectedLanguage = OEXInterface.getCCSelectedLanguage(), let transcriptURL = video.summary?.transcripts?[ccSelectedLanguage] as? String, !ccSelectedLanguage.isEmpty, !transcriptURL.isEmpty, ccSelectedLanguage != captionLanguageNone {
            url = transcriptURL
        }
        else if let transcriptURL = video.summary?.transcripts?[devicelangue] as? String,!devicelangue.isEmpty, !transcriptURL.isEmpty {
            // if no language is selected, give preference to device language
            url = transcriptURL
        }
        else if let transcriptURL = video.summary?.transcripts?["en"] as? String, !transcriptURL.isEmpty {
            // if no language is selected, and transcripts are not available for device langue, look for english
            url = transcriptURL
        }
        else if let transcriptURL = video.summary?.transcripts?.values.first as? String  {
            url = transcriptURL
        }
        return url
    }
    
    func loadTranscripts() {
        closedCaptioning(at: captionURL)
    }
    
    private func initializeSubtitle() {
        loadTranscripts()
        NotificationCenter.default.oex_addObserver(observer: self, name: DL_COMPLETE) { (notification, observer, _) -> Void in
            observer.downloadedTranscript(notification: notification)
        }
    }
    
    private func downloadedTranscript(notification: NSNotification) {
        if let task = notification.userInfo?[DL_COMPLETE_N_TASK] as? URLSessionDownloadTask, let taskURL = task.response?.url {
            if taskURL.absoluteString == captionURL {
                closedCaptioning(at: captionURL)
            }
        }
    }
    
   private func closedCaptioning(at URLString: String?) {
        if let localFile: String = OEXFileUtility.filePath(forRequestKey: URLString) {
            // File to string
            if FileManager.default.fileExists(atPath: localFile) {
                // File to string
                do {
                    let transcript = try String(contentsOfFile: localFile, encoding: .utf8)
                    transcriptParser.parse(transcript: transcript, completion: { (success, error) in
                        transcripts = transcriptParser.transcripts
                        delegate?.transcriptsLoaded(manager: self, transcripts: transcripts)
                    })
                }
                catch _ {}
            }
            else {
                environment.interface?.download(withRequest: URLString, forceUpdate: false)
            }
        }
    }
    
    func transcript(at time: TimeInterval) -> String {
        let filteredSubTitles = transcripts.filter { return time > $0.start && time < $0.end }
        return filteredSubTitles.first?.text ?? ""
    }
}
