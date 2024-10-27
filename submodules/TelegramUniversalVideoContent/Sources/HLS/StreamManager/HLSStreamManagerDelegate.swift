//
//  HLSStreamManagerDelegate.swift
//  Telegram
//
//  Created by Vlad on 27.10.2024.
//

import HLSObjcModule

protocol HLSStreamManagerDelegate: AnyObject {
    
    func streamManager(_ streamManager: HLSStreamManager, didStartPlay track: HLSStreamManager.Track)
    func streamManager(_ streamManager: HLSStreamManager, didPausePlay track: HLSStreamManager.Track)
    func streamManager(_ streamManager: HLSStreamManager, didStopPlay track: HLSStreamManager.Track)
    func streamManager(_ streamManager: HLSStreamManager, didEndPlay track: HLSStreamManager.Track)
    func streamManager(_ streamManager: HLSStreamManager, nextRenderFrame frame: HLSDecoderFrame, for track: HLSStreamManager.Track)
    func streamManager(_ streamManager: HLSStreamManager, error: Error, for track: HLSStreamManager.Track)
    
}
