//
//  File.swift
//  
//
//  Created by Jason Lew-Rapai on 12/5/22.
//

import Foundation
import Combine
import SwiftUI

public protocol BusyIndicatorServiceProtocol: AnyObject {
    var queue: AnyPublisher<Int, Never> { get }
    var busyIndicator: BusyIndicator { get }
    func enqueue() -> BusySubject
}

public class BusyIndicatorService: BusyIndicatorServiceProtocol {
    let configuration: BusyIndicatorConfiguration
    
    private var _queue: CurrentValueSubject<Int, Never> = CurrentValueSubject(0)
    public var queue: AnyPublisher<Int, Never> { self._queue.eraseToAnyPublisher() }

    public private(set) lazy var busyIndicator: BusyIndicator = BusyIndicator(busy: getIsBusyPublisher())
    
    private let queueDispatchQueue: DispatchQueue = DispatchQueue(label: "BusyIndicatorService-\(UUID().uuidString)")
    private let _enqueue: PassthroughSubject<Void, Never> = PassthroughSubject()
    private let _dequeue: PassthroughSubject<Void, Never> = PassthroughSubject()
    
    private var cancelBag = Set<AnyCancellable>()
    
    public init(configuration: BusyIndicatorConfiguration = BusyIndicatorConfiguration()) {
        self.configuration = configuration
        bind()
    }
    
    private func bind() {
        self._enqueue
            .receive(on: self.queueDispatchQueue)
            .withLatestFrom(self._queue)
            .map { $0 + 1 }
            .sink(receiveValue: { [_queue] in
                _queue.send($0)
            })
            .store(in: &self.cancelBag)

        self._dequeue
            .receive(on: self.queueDispatchQueue)
            .withLatestFrom(self._queue)
            .map { max(0, $0 - 1) }
            .sink(receiveValue: { [_queue] in
                _queue.send($0)
            })
            .store(in: &self.cancelBag)
    }
    
    public func enqueue() -> BusySubject {
        self._enqueue.send()
        return BusySubject(delegate: self)
    }
    
    private func getIsBusyPublisher() -> AnyPublisher<Bool, Never> {
        return self._queue
            .receive(on: self.queueDispatchQueue)
            .flatMapLatest { [configuration, queueDispatchQueue] queue -> AnyPublisher<Bool, Never> in
                if queue == 0 {
                    return Just(false).eraseToAnyPublisher()
                } else {
                    return Just(true)
                        .delay(for: .milliseconds(configuration.showBusyIndicatorDelay), scheduler: queueDispatchQueue)
                        .eraseToAnyPublisher()
                }
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}

extension BusyIndicatorService: BusySubjectDelegate {
    func busySubjectDidDequeue(_ source: BusySubject) {
        self._dequeue.send()
    }
}
