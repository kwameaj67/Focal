//
//  MainThreadDelivery.swift
//  FocalCore
//
//  The single hop that pins every host-facing callback to the main thread.
//
//  Capture events originate off the main thread — `AVFoundation` invokes its
//  photo and movie delegates on its own background queues, and the engines run
//  their work on a serial `sessionQueue`. Rather than leave the delivery thread
//  up to whichever internal queue produced the event, the public handler
//  bundles (`FCPhotoHandlers` / `FCVideoHandlers`) route every closure through
//  `onMainThread` so hosts can touch UIKit / SwiftUI state directly, without
//  marshalling. See the threading note on those types.
//

import Foundation

/// Runs `work` on the main thread: synchronously when the caller is already on
/// it — so ordering and re-entrancy match a plain call — otherwise dispatched
/// asynchronously to the main queue.
///
/// `package`, not `public`: it is the internal mechanism behind the handlers'
/// main-thread guarantee, not something hosts program against.
package func onMainThread(_ work: @escaping () -> Void) {
    if Thread.isMainThread {
        work()
    } else {
        DispatchQueue.main.async(execute: work)
    }
}
