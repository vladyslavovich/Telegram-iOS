//
//  HLSTask.swift
//  Telegram
//
//  Created byVlad on 20.10.2024.
//

import Foundation

final class HLSTask {
    
    public typealias Closure = (Controller) -> Void
    
    var isCancelled: Bool = false
    
    private let taskBlock: Closure
    private weak var controller: Controller?
    
    init(taskBlock: @escaping Closure) {
        self.taskBlock = taskBlock
    }
    
    func perform(on queue: DispatchQueue, handler: @escaping () -> Void) {
        queue.async {
            guard !self.isCancelled else {
                return
            }
            
            let controller = Controller(queue: queue, handler: handler)
            self.controller = controller
            self.taskBlock(controller)
        }
    }
    
}

extension HLSTask {
    
    final class Controller {
        
        fileprivate let isCancelled: Bool = false
        fileprivate let queue: DispatchQueue
        fileprivate let handler: () -> Void
        
        fileprivate init(queue: DispatchQueue, handler: @escaping () -> Void) {
            self.queue = queue
            self.handler = handler
        }
        
        func finish() {
            queue.async {
                print("HLSTask finished")
                self.handler()
            }
        }
        
    }
    
}
extension HLSTask {
    
    static func sequence(_ tasks: [HLSTask]) -> HLSTask {
        var sequence = tasks
        return HLSTask { controller in
            func performNext(using controller: Controller) {
                guard !sequence.isEmpty && !controller.isCancelled else {
                    controller.finish()
                    return
                }
                
                let task = sequence.removeFirst()
                
                task.perform(on: controller.queue) {
                    performNext(using: controller)
                }
            }
            
            performNext(using: controller)
        }
    }
    
}
