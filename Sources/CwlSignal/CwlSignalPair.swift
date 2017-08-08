//
//  CwlSignalPair.swift
//  CwlSignal
//
//  Created by Matt Gallagher on 2017/06/27.
//  Copyright © 2017 Matt Gallagher ( http://cocoawithlove.com ). All rights reserved.
//
//  Permission to use, copy, modify, and/or distribute this software for any purpose with or without
//  fee is hereby granted, provided that the above copyright notice and this permission notice
//  appear in all copies.
//
//  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS
//  SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
//  AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
//  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
//  NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE
//  OF THIS SOFTWARE.
//

#if SWIFT_PACKAGE
	import Foundation
	import CwlUtils
#endif

/// A `SignalPair` and its common typealiases, `Channel`, `MultiChannel` and `Variable` form basic wrappers around a `SignalInput`/`Signal` pair.
///
/// This class exists for syntactic convenience when building a series of pipeline stages.
/// e.g.:
///		let (input, signal) = Channel<Int>().map { $0 + 1 }.pair
///
/// Every transform in the CwlSignal library that can be applied to `Signal<OutputValue>` can also be applied to `SignalChannel<OutputValue>`. Where possible, the result is another `SignalChannel` so the result can be immediately transformed again.
///
/// A `Channel()` function exists in global scope to simplify syntax further in situations where the result type is already constrained:
///		someFunction(signalInput: Channel().map { $0 + 1 }.join(to: multiInputChannelFromElsewhere))
///
/// For similar syntactic reasons, `SignalInput<OutputValue>` includes static versions of all of those `SignalChannel` methods where the result is either a `SignalInput<OutputValue>` or a `SignalChannel` where `InputValue` remains unchanged.
/// e.g.:
///		someFunction(signalInput: .join(to: multiInputChannelFromElsewhere))
/// Unfortunately, due to limitations in Swift, this bare `SiganlInput` approach works only in those cases where the channel is a single stage ending in a `SignalInput<OutputValue>`.
public struct SignalPair<InputValue, Input: SignalInput<InputValue>, OutputValue, Output: Signal<OutputValue>> {
	public let input: Input
	public let signal: Output
	public init(input: Input, signal: Output) {
		self.input = input
		self.signal = signal
	}
	public init(_ tuple: (Input, Output)) {
		self.init(input: tuple.0, signal: tuple.1)
	}
	public func next<U, SU: Signal<U>>(_ compose: (Signal<OutputValue>) throws -> SU) rethrows -> SignalPair<InputValue, Input, U, SU> {
		return try SignalPair<InputValue, Input, U, SU>(input: input, signal: compose(signal))
	}
	public func final<U>(_ compose: (Signal<OutputValue>) throws -> U) rethrows -> (input: Input, output: U) {
		return try (input, compose(signal))
	}
	public func consume(_ compose: (Signal<OutputValue>) throws -> ()) rethrows -> Input {
		try compose(signal)
		return input
	}
	public var tuple: (input: Input, signal: Output) { return (input: input, signal: signal) }
}

public typealias Channel<Value> = SignalPair<Value, SignalInput<Value>, Value, Signal<Value>>
public typealias MultiChannel<Value> = SignalPair<Value, SignalMultiInput<Value>, Value, Signal<Value>>
public typealias Variable<Value> = SignalPair<Value, SignalMultiInput<Value>, Value, SignalMulti<Value>>
public typealias Reducer<InputValue, OutputValue> = SignalPair<InputValue, SignalMultiInput<InputValue>, OutputValue, SignalMulti<OutputValue>>

extension SignalPair where InputValue == OutputValue, Input == SignalInput<InputValue>, Output == Signal<OutputValue> {
	public init() {
		self.init(Signal<InputValue>.create())
	}
}

extension SignalPair where InputValue == OutputValue, Input == SignalMultiInput<InputValue>, Output == Signal<OutputValue> {
	public init() {
		self.init(Signal<InputValue>.createMultiInput())
	}
}

extension SignalPair where InputValue == OutputValue, Input == SignalMultiInput<InputValue>, Output == SignalMulti<OutputValue> {
	public init(continuous: Bool = true) {
		let c = MultiChannel<OutputValue>()
		self = continuous ? c.continuous() : c.multicast()
	}
	public init(initialValue: OutputValue) {
		self = MultiChannel<OutputValue>().continuous(initialValue: initialValue)
	}
}

extension SignalPair where Input == SignalMultiInput<InputValue>, Output == SignalMulti<OutputValue> {
	public init(initialState: OutputValue, _ processor: @escaping (_ state: OutputValue, _ input: InputValue) -> OutputValue) {
		self = MultiChannel<InputValue>().map(initialState: initialState) { (state: inout OutputValue, input: InputValue) -> OutputValue in
			let new = processor(state, input)
			state = new
			return new
		}.continuous(initialValue: initialState)
	}
}

// Implementation of Signal.swift
extension SignalPair {
	public func subscribe(context: Exec = .direct, handler: @escaping (Result<OutputValue>) -> Void) -> (input: Input, endpoint: SignalEndpoint<OutputValue>) {
		let tuple = final { $0.subscribe(context: context, handler: handler) }
		return (input: tuple.input, endpoint: tuple.output)
	}
	
	public func subscribeAndKeepAlive(context: Exec = .direct, handler: @escaping (Result<OutputValue>) -> Bool) -> Input {
		return final { $0.subscribeAndKeepAlive(context: context, handler: handler) }.input
	}
	
	public func join(to: SignalInput<OutputValue>) -> Input {
		return final { $0.join(to: to) }.input
	}
	
	public func junction() -> (input: Input, junction: SignalJunction<OutputValue>) {
		let tuple = final { $0.junction() }
		return (input: tuple.input, junction: tuple.output)
	}
	
	public func transform<U>(context: Exec = .direct, handler: @escaping (Result<OutputValue>, SignalNext<U>) -> Void) -> SignalPair<InputValue, Input, U, Signal<U>> {
		return next { $0.transform(context: context, handler: handler) }
	}
	
	public func transform<S, U>(initialState: S, context: Exec = .direct, handler: @escaping (inout S, Result<OutputValue>, SignalNext<U>) -> Void) -> SignalPair<InputValue, Input, U, Signal<U>> {
		return next { $0.transform(initialState: initialState, context: context, handler: handler) }
	}
	
	public func combine<U, V>(second: Signal<U>, context: Exec = .direct, handler: @escaping (EitherResult2<OutputValue, U>, SignalNext<V>) -> Void) -> SignalPair<InputValue, Input, V, Signal<V>> {
		return next { $0.combine(second: second, context: context, handler: handler) }
	}
	
	public func combine<U, V, W>(second: Signal<U>, third: Signal<V>, context: Exec = .direct, handler: @escaping (EitherResult3<OutputValue, U, V>, SignalNext<W>) -> Void) -> SignalPair<InputValue, Input, W, Signal<W>> {
		return next { $0.combine(second: second, third: third, context: context, handler: handler) }
	}
	
	public func combine<U, V, W, X>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, handler: @escaping (EitherResult4<OutputValue, U, V, W>, SignalNext<X>) -> Void) -> SignalPair<InputValue, Input, X, Signal<X>> {
		return next { $0.combine(second: second, third: third, fourth: fourth, context: context, handler: handler) }
	}
	
	public func combine<U, V, W, X, Y>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, handler: @escaping (EitherResult5<OutputValue, U, V, W, X>, SignalNext<Y>) -> Void) -> SignalPair<InputValue, Input, Y, Signal<Y>> {
		return next { $0.combine(second: second, third: third, fourth: fourth, fifth: fifth, context: context, handler: handler) }
	}
	
	public func combine<S, U, V>(initialState: S, second: Signal<U>, context: Exec = .direct, handler: @escaping (inout S, EitherResult2<OutputValue, U>, SignalNext<V>) -> Void) -> SignalPair<InputValue, Input, V, Signal<V>> {
		return next { $0.combine(initialState: initialState, second: second, context: context, handler: handler) }
	}
	
	public func combine<S, U, V, W>(initialState: S, second: Signal<U>, third: Signal<V>, context: Exec = .direct, handler: @escaping (inout S, EitherResult3<OutputValue, U, V>, SignalNext<W>) -> Void) -> SignalPair<InputValue, Input, W, Signal<W>> {
		return next { $0.combine(initialState: initialState, second: second, third: third, context: context, handler: handler) }
	}
	
	public func combine<S, U, V, W, X>(initialState: S, second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, handler: @escaping (inout S, EitherResult4<OutputValue, U, V, W>, SignalNext<X>) -> Void) -> SignalPair<InputValue, Input, X, Signal<X>> {
		return next { $0.combine(initialState: initialState, second: second, third: third, fourth: fourth, context: context, handler: handler) }
	}
	
	public func combine<S, U, V, W, X, Y>(initialState: S, second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, handler: @escaping (inout S, EitherResult5<OutputValue, U, V, W, X>, SignalNext<Y>) -> Void) -> SignalPair<InputValue, Input, Y, Signal<Y>> {
		return next { $0.combine(initialState: initialState, second: second, third: third, fourth: fourth, fifth: fifth, context: context, handler: handler) }
	}
	
	public func continuous(initialValue: OutputValue) -> SignalPair<InputValue, Input, OutputValue, SignalMulti<OutputValue>> {
		return next { $0.continuous(initialValue: initialValue) }
	}
	
	public func continuous() -> SignalPair<InputValue, Input, OutputValue, SignalMulti<OutputValue>> {
		return next { $0.continuous() }
	}
	
	public func continuousWhileActive() -> SignalPair<InputValue, Input, OutputValue, SignalMulti<OutputValue>> {
		return next { $0.continuousWhileActive() }
	}
	
	public func playback() -> SignalPair<InputValue, Input, OutputValue, SignalMulti<OutputValue>> {
		return next { $0.playback() }
	}
	
	public func cacheUntilActive() -> SignalPair<InputValue, Input, OutputValue, SignalMulti<OutputValue>> {
		return next { $0.playback() }
	}
	
	public func multicast() -> SignalPair<InputValue, Input, OutputValue, SignalMulti<OutputValue>> {
		return next { $0.playback() }
	}
	
	public func customActivation(initialValues: Array<OutputValue> = [], context: Exec = .direct, updater: @escaping (_ cachedValues: inout Array<OutputValue>, _ cachedError: inout Error?, _ incoming: Result<OutputValue>) -> Void) -> SignalPair<InputValue, Input, OutputValue, SignalMulti<OutputValue>> {
		return next { $0.customActivation(initialValues: initialValues, context: context, updater: updater) }
	}
	
	public func capture() -> (input: Input, capture: SignalCapture<OutputValue>) {
		let tuple = final { $0.capture() }
		return (input: tuple.input, capture: tuple.output)
	}
}

// Implementation of SignalExtensions.swift
extension SignalPair {
	public func subscribeValues(context: Exec = .direct, handler: @escaping (OutputValue) -> Void) -> (input: Input, endpoint: SignalEndpoint<OutputValue>) {
		let tuple = final { $0.subscribeValues(context: context, handler: handler) }
		return (input: tuple.input, endpoint: tuple.output)
	}
	
	public func subscribeValuesAndKeepAlive(context: Exec = .direct, handler: @escaping (OutputValue) -> Bool) -> Input {
		signal.subscribeValuesAndKeepAlive(context: context, handler: handler)
		return input
	}
	
	public func stride(count: Int, initialSkip: Int = 0) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.stride(count: count, initialSkip: initialSkip) }
	}
	
	public func transformFlatten<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, _ processor: @escaping (OutputValue, SignalMergedInput<U>) -> ()) -> SignalPair<InputValue, Input, U, Signal<U>>{
		return next { $0.transformFlatten(closePropagation: closePropagation, context: context, processor) }
	}
	
	public func transformFlatten<S, U>(initialState: S, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, _ processor: @escaping (inout S, OutputValue, SignalMergedInput<U>) -> ()) -> SignalPair<InputValue, Input, U, Signal<U>> {
		return next { $0.transformFlatten(initialState: initialState, closePropagation: closePropagation, context: context, processor) }
	}
	
	public func valueDurations<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, duration: @escaping (OutputValue) -> Signal<U>) -> SignalPair<InputValue, Input, (Int, OutputValue?), Signal<(Int, OutputValue?)>> {
		return next { $0.valueDurations(closePropagation: closePropagation, context: context, duration: duration) }
	}
	
	public func valueDurations<U, V>(initialState: V, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, duration: @escaping (inout V, OutputValue) -> Signal<U>) -> SignalPair<InputValue, Input, (Int, OutputValue?), Signal<(Int, OutputValue?)>> {
		return next { $0.valueDurations(initialState: initialState, closePropagation: closePropagation, context: context, duration: duration) }
	}
	
	public func join(to: SignalMergedInput<OutputValue>, closePropagation: SignalClosePropagation = .none, removeOnDeactivate: Bool = false) -> Input {
		signal.join(to: to, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate)
		return input
	}
	
	public func cancellableJoin(to: SignalMergedInput<OutputValue>, closePropagation: SignalClosePropagation = .none, removeOnDeactivate: Bool = false) -> (input: Input, cancellable: Cancellable) {
		let tuple = final { $0.cancellableJoin(to: to, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate) }
		return (input: tuple.input, cancellable: tuple.output)
	}
	
	public func join(to: SignalMultiInput<OutputValue>) -> Input {
		return final { $0.join(to: to) }.input
	}
	
	public func cancellableJoin(to: SignalMultiInput<OutputValue>) -> (input: Input, cancellable: Cancellable) {
		let tuple = final { $0.cancellableJoin(to: to) }
		return (input: tuple.input, cancellable: tuple.output)
	}
	
	public func pollingEndpoint() -> (input: Input, endpoint: SignalPollingEndpoint<OutputValue>) {
		let tuple = final { SignalPollingEndpoint(signal: $0) }
		return (input: tuple.input, endpoint: tuple.output)
	}
	
	public func toggle(initialState: Bool = false) -> SignalPair<InputValue, Input, Bool, Signal<Bool>> {
		return next { $0.toggle(initialState: initialState) }
	}
}

// Implementation of SignalReactive.swift
extension SignalPair {
	public func buffer<U>(boundaries: Signal<U>) -> SignalPair<InputValue, Input, [OutputValue], Signal<[OutputValue]>> {
		return next { $0.buffer(boundaries: boundaries) }
	}
	
	public func buffer<U>(windows: Signal<Signal<U>>) -> SignalPair<InputValue, Input, [OutputValue], Signal<[OutputValue]>> {
		return next { $0.buffer(windows: windows) }
	}
	
	public func buffer(count: UInt, skip: UInt) -> SignalPair<InputValue, Input, [OutputValue], Signal<[OutputValue]>> {
		return next { $0.buffer(count: count, skip: skip) }
	}
	
	public func buffer(interval: DispatchTimeInterval, count: Int = Int.max, continuous: Bool = true, context: Exec = .direct) -> SignalPair<InputValue, Input, [OutputValue], Signal<[OutputValue]>> {
		return next { $0.buffer(interval: interval, count: count, continuous: continuous, context: context) }
	}
	
	public func buffer(count: UInt) -> SignalPair<InputValue, Input, [OutputValue], Signal<[OutputValue]>> {
		return next { $0.buffer(count: count, skip: count) }
	}
	
	public func buffer(interval: DispatchTimeInterval, timeshift: DispatchTimeInterval, context: Exec = .direct) -> SignalPair<InputValue, Input, [OutputValue], Signal<[OutputValue]>> {
		return next { $0.buffer(interval: interval, timeshift: timeshift, context: context) }
	}
	
	public func filterMap<U>(context: Exec = .direct, _ processor: @escaping (OutputValue) -> U?) -> SignalPair<InputValue, Input, U, Signal<U>> {
		return next { $0.filterMap(context: context, processor) }
	}
	
	public func filterMap<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, OutputValue) -> U?) -> SignalPair<InputValue, Input, U, Signal<U>> {
		return next { $0.filterMap(initialState: initialState, context: context, processor) }
	}
	
	public func failableMap<U>(context: Exec = .direct, _ processor: @escaping (OutputValue) throws -> U) -> SignalPair<InputValue, Input, U, Signal<U>> {
		return next { $0.failableMap(context: context, processor) }
	}
	
	public func failableMap<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, OutputValue) throws -> U) -> SignalPair<InputValue, Input, U, Signal<U>> {
		return next { $0.failableMap(initialState: initialState, context: context, processor) }
	}
	
	public func failableFilterMap<U>(context: Exec = .direct, _ processor: @escaping (OutputValue) throws -> U?) -> SignalPair<InputValue, Input, U, Signal<U>> {
		return next { $0.failableFilterMap(context: context, processor) }
	}
	
	public func failableFilterMap<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, OutputValue) -> U?) throws -> SignalPair<InputValue, Input, U, Signal<U>> {
		return next { $0.failableFilterMap(initialState: initialState, context: context, processor) }
	}
	
	public func flatMap<U>(context: Exec = .direct, _ processor: @escaping (OutputValue) -> Signal<U>) -> SignalPair<InputValue, Input, U, Signal<U>> {
		return next { $0.flatMap(context: context, processor) }
	}
	
	public func flatMapFirst<U>(context: Exec = .direct, _ processor: @escaping (OutputValue) -> Signal<U>) -> SignalPair<InputValue, Input, U, Signal<U>> {
		return next { $0.flatMapFirst(context: context, processor) }
	}
	
	public func flatMapLatest<U>(context: Exec = .direct, _ processor: @escaping (OutputValue) -> Signal<U>) -> SignalPair<InputValue, Input, U, Signal<U>> {
		return next { $0.flatMapLatest(context: context, processor) }
	}
	
	public func flatMap<U, V>(initialState: V, context: Exec = .direct, _ processor: @escaping (inout V, OutputValue) -> Signal<U>) -> SignalPair<InputValue, Input, U, Signal<U>> {
		return next { $0.flatMap(initialState: initialState, context: context, processor) }
	}
	
	public func concatMap<U>(context: Exec = .direct, _ processor: @escaping (OutputValue) -> Signal<U>) -> SignalPair<InputValue, Input, U, Signal<U>> {
		return next { $0.concatMap(context: context, processor) }
	}
	
	public func groupBy<U: Hashable>(context: Exec = .direct, _ processor: @escaping (OutputValue) -> U) -> SignalPair<InputValue, Input, (U, Signal<OutputValue>), Signal<(U, Signal<OutputValue>)>> {
		return next { $0.groupBy(context: context, processor) }
	}
	
	public func map<U>(context: Exec = .direct, _ processor: @escaping (OutputValue) -> U) -> SignalPair<InputValue, Input, U, Signal<U>> {
		return next { $0.map(context: context, processor) }
	}
	
	public func map<U, V>(initialState: V, context: Exec = .direct, _ processor: @escaping (inout V, OutputValue) -> U) -> SignalPair<InputValue, Input, U, Signal<U>> {
		return next { $0.map(initialState: initialState, context: context, processor) }
	}
	
	public func scan<U>(initialState: U, context: Exec = .direct, _ processor: @escaping (U, OutputValue) -> U) -> SignalPair<InputValue, Input, U, Signal<U>> {
		return next { $0.scan(initialState: initialState, context: context, processor) }
	}
	
	public func window<U>(boundaries: Signal<U>) -> SignalPair<InputValue, Input, Signal<OutputValue>, Signal<Signal<OutputValue>>> {
		return next { $0.window(boundaries: boundaries) }
	}
	
	public func window<U>(windows: Signal<Signal<U>>) -> SignalPair<InputValue, Input, Signal<OutputValue>, Signal<Signal<OutputValue>>> {
		return next { $0.window(windows: windows) }
	}
	
	public func window(count: UInt, skip: UInt) -> SignalPair<InputValue, Input, Signal<OutputValue>, Signal<Signal<OutputValue>>> {
		return next { $0.window(count: count, skip: skip) }
	}
	
	public func window(interval: DispatchTimeInterval, count: Int = Int.max, continuous: Bool = true, context: Exec = .direct) -> SignalPair<InputValue, Input, Signal<OutputValue>, Signal<Signal<OutputValue>>> {
		return next { $0.window(interval: interval, count: count, continuous: continuous, context: context) }
	}
	
	public func window(count: UInt) -> SignalPair<InputValue, Input, Signal<OutputValue>, Signal<Signal<OutputValue>>> {
		return next { $0.window(count: count, skip: count) }
	}
	
	public func window(interval: DispatchTimeInterval, timeshift: DispatchTimeInterval, context: Exec = .direct) -> SignalPair<InputValue, Input, Signal<OutputValue>, Signal<Signal<OutputValue>>> {
		return next { $0.window(interval: interval, timeshift: timeshift, context: context) }
	}
	
	public func debounce(interval: DispatchTimeInterval, flushOnClose: Bool = true, context: Exec = .direct) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.debounce(interval: interval, flushOnClose: flushOnClose, context: context) }
	}
	
	public func throttleFirst(interval: DispatchTimeInterval, context: Exec = .direct) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.throttleFirst(interval: interval, context: context) }
	}
}

extension SignalPair where OutputValue: Hashable {
	public func distinct() -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.distinct() }
	}
	
	public func distinctUntilChanged() -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.distinctUntilChanged() }
	}
}

extension SignalPair {
	public func distinctUntilChanged(context: Exec = .direct, comparator: @escaping (OutputValue, OutputValue) -> Bool) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.distinctUntilChanged(context: context, comparator: comparator) }
	}
	
	public func elementAt(_ index: UInt) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.elementAt(index) }
	}
	
	public func filter(context: Exec = .direct, matching: @escaping (OutputValue) -> Bool) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.filter(context: context, matching: matching) }
	}
	
	public func ofType<U>(_ type: U.Type) -> SignalPair<InputValue, Input, U, Signal<U>> {
		return next { $0.ofType(type) }
	}
	
	public func first(context: Exec = .direct, matching: @escaping (OutputValue) -> Bool = { _ in true }) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.first(context: context, matching: matching) }
	}
	
	public func single(context: Exec = .direct, matching: @escaping (OutputValue) -> Bool = { _ in true }) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.single(context: context, matching: matching) }
	}
	
	public func ignoreElements() -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.ignoreElements() }
	}
	
	public func ignoreElements<S: Sequence>(endWith: @escaping (Error) -> (S, Error)?) -> SignalPair<InputValue, Input, S.Iterator.Element, Signal<S.Iterator.Element>> {
		return next { $0.ignoreElements(endWith: endWith) }
	}
	
	public func ignoreElements<U>(endWith value: U, conditional: @escaping (Error) -> Error? = { e in e }) -> SignalPair<InputValue, Input, U, Signal<U>> {
		return next { $0.ignoreElements(endWith: value, conditional: conditional) }
	}
	
	public func last(context: Exec = .direct, matching: @escaping (OutputValue) -> Bool = { _ in true }) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.last(context: context, matching: matching) }
	}
	
	public func sample(_ trigger: Signal<()>) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.sample(trigger) }
	}
	
	public func sampleCombine<U>(_ trigger: Signal<U>) -> SignalPair<InputValue, Input, (sample: OutputValue, trigger: U), Signal<(sample: OutputValue, trigger: U)>> {
		return next { $0.sampleCombine(trigger) }
	}
	
	public func latest<U>(_ source: Signal<U>) -> SignalPair<InputValue, Input, U, Signal<U>> {
		return next { $0.latest(source) }
	}
	
	public func latestCombine<U>(_ source: Signal<U>) -> SignalPair<InputValue, Input, (trigger: OutputValue, sample: U), Signal<(trigger: OutputValue, sample: U)>> {
		return next { $0.latestCombine(source) }
	}
	
	public func skip(_ count: Int) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.skip(count) }
	}
	
	public func skipLast(_ count: Int) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.skipLast(count) }
	}
	
	public func take(_ count: Int) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.take(count) }
	}
	
	public func takeLast(_ count: Int) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.takeLast(count) }
	}
}

extension SignalPair {
	
	public func combineLatest<U, V>(second: Signal<U>, context: Exec = .direct, _ processor: @escaping (OutputValue, U) -> V) -> SignalPair<InputValue, Input, V, Signal<V>> {
		return next { $0.combineLatest(second: second, context: context, processor) }
	}
	
	public func combineLatest<U, V, W>(second: Signal<U>, third: Signal<V>, context: Exec = .direct, _ processor: @escaping (OutputValue, U, V) -> W) -> SignalPair<InputValue, Input, W, Signal<W>> {
		return next { $0.combineLatest(second: second, third: third, context: context, processor) }
	}
	
	public func combineLatest<U, V, W, X>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, _ processor: @escaping (OutputValue, U, V, W) -> X) -> SignalPair<InputValue, Input, X, Signal<X>> {
		return next { $0.combineLatest(second: second, third: third, fourth: fourth, context: context, processor) }
	}
	
	public func combineLatest<U, V, W, X, Y>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, _ processor: @escaping (OutputValue, U, V, W, X) -> Y) -> SignalPair<InputValue, Input, Y, Signal<Y>> {
		return next { $0.combineLatest(second: second, third: third, fourth: fourth, fifth: fifth, context: context, processor) }
	}
	
	public func join<U, V, W, X>(withRight: Signal<U>, leftEnd: @escaping (OutputValue) -> Signal<V>, rightEnd: @escaping (U) -> Signal<W>, context: Exec = .direct, _ processor: @escaping ((OutputValue, U)) -> X) -> SignalPair<InputValue, Input, X, Signal<X>> {
		return next { $0.join(withRight: withRight, leftEnd: leftEnd, rightEnd: rightEnd, context: context, processor) }
	}
	
	public func groupJoin<U, V, W, X>(withRight: Signal<U>, leftEnd: @escaping (OutputValue) -> Signal<V>, rightEnd: @escaping (U) -> Signal<W>, context: Exec = .direct, _ processor: @escaping ((OutputValue, Signal<U>)) -> X) -> SignalPair<InputValue, Input, X, Signal<X>> {
		return next { $0.groupJoin(withRight: withRight, leftEnd: leftEnd, rightEnd: rightEnd, context: context, processor) }
	}
	
	public func mergeWith(_ sources: Signal<OutputValue>...) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.mergeWith(sources) }
	}
	
	public func mergeWith<S: Sequence>(_ sequence: S) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> where S.Iterator.Element == Signal<OutputValue> {
		return next { $0.mergeWith(sequence) }
	}
	
	public func startWith<S: Sequence>(_ sequence: S) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> where S.Iterator.Element == OutputValue {
		return next { $0.startWith(sequence) }
	}
	
	public func endWith<U: Sequence>(_ sequence: U, conditional: @escaping (Error) -> Error? = { e in e }) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> where U.Iterator.Element == OutputValue {
		return next { $0.endWith(sequence, conditional: conditional) }
	}
	
	func endWith(_ value: OutputValue, conditional: @escaping (Error) -> Error? = { e in e }) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.endWith(value, conditional: conditional) }
	}
	
	public func zip<U>(second: Signal<U>) -> SignalPair<InputValue, Input, (OutputValue, U), Signal<(OutputValue, U)>> {
		return next { $0.zip(second: second) }
	}
	
	public func zip<U, V>(second: Signal<U>, third: Signal<V>) -> SignalPair<InputValue, Input, (OutputValue, U, V), Signal<(OutputValue, U, V)>> {
		return next { $0.zip(second: second, third: third) }
	}
	
	public func zip<U, V, W>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>) -> SignalPair<InputValue, Input, (OutputValue, U, V, W), Signal<(OutputValue, U, V, W)>> {
		return next { $0.zip(second: second, third: third, fourth: fourth) }
	}
	
	public func zip<U, V, W, X>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>) -> SignalPair<InputValue, Input, (OutputValue, U, V, W, X), Signal<(OutputValue, U, V, W, X)>> {
		return next { $0.zip(second: second, third: third, fourth: fourth, fifth: fifth) }
	}
	
	public func catchError<S: Sequence>(context: Exec = .direct, recover: @escaping (Error) -> (S, Error)) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> where S.Iterator.Element == OutputValue {
		return next { $0.catchError(context: context, recover: recover) }
	}
}

extension SignalPair {
	public func catchError(context: Exec = .direct, recover: @escaping (Error) -> Signal<OutputValue>?) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.catchError(context: context, recover: recover) }
	}
	
	public func retry<U>(_ initialState: U, context: Exec = .direct, shouldRetry: @escaping (inout U, Error) -> DispatchTimeInterval?) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.retry(initialState, context: context, shouldRetry: shouldRetry) }
	}
	
	public func retry(count: Int, delayInterval: DispatchTimeInterval, context: Exec = .direct) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.retry(count: count, delayInterval: delayInterval, context: context) }
	}
	
	public func delay<U>(initialState: U, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, offset: @escaping (inout U, OutputValue) -> DispatchTimeInterval) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.delay(initialState: initialState, closePropagation: closePropagation, context: context, offset: offset) }
	}
	
	public func delay(interval: DispatchTimeInterval, context: Exec = .direct) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.delay(interval: interval, context: context) }
	}
	
	public func delay<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, offset: @escaping (OutputValue) -> Signal<U>) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.delay(closePropagation: closePropagation, context: context, offset: offset) }
	}
	
	public func delay<U, V>(initialState: V, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, offset: @escaping (inout V, OutputValue) -> Signal<U>) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.delay(initialState: initialState, closePropagation: closePropagation, context: context, offset: offset) }
	}
	
	public func onActivate(context: Exec = .direct, handler: @escaping () -> ()) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.onActivate(context: context, handler: handler) }
	}
	
	public func onDeactivate(context: Exec = .direct, handler: @escaping () -> ()) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.onDeactivate(context: context, handler: handler) }
	}
	
	public func onResult(context: Exec = .direct, handler: @escaping (Result<OutputValue>) -> ()) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.onResult(context: context, handler: handler) }
	}
	
	public func onValue(context: Exec = .direct, handler: @escaping (OutputValue) -> ()) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.onValue(context: context, handler: handler) }
	}
	
	public func onError(context: Exec = .direct, handler: @escaping (Error) -> ()) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.onError(context: context, handler: handler) }
	}
	
	public func materialize() -> SignalPair<InputValue, Input, Result<OutputValue>, Signal<Result<OutputValue>>> {
		return next { $0.materialize() }
	}
}


extension SignalPair {
	
	public func timeInterval(context: Exec = .direct) -> SignalPair<InputValue, Input, Double, Signal<Double>> {
		return next { $0.timeInterval(context: context) }
	}
	
	public func timeout(interval: DispatchTimeInterval, resetOnValue: Bool = true, context: Exec = .direct) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.timeout(interval: interval, resetOnValue: resetOnValue, context: context) }
	}
	
	public func timestamp(context: Exec = .direct) -> SignalPair<InputValue, Input, (OutputValue, DispatchTime), Signal<(OutputValue, DispatchTime)>> {
		return next { $0.timestamp(context: context) }
	}
}


extension SignalPair {
	
	public func all(context: Exec = .direct, test: @escaping (OutputValue) -> Bool) -> SignalPair<InputValue, Input, Bool, Signal<Bool>> {
		return next { $0.all(context: context, test: test) }
	}
	
	public func some(context: Exec = .direct, test: @escaping (OutputValue) -> Bool) -> SignalPair<InputValue, Input, Bool, Signal<Bool>> {
		return next { $0.some(context: context, test: test) }
	}
}

extension SignalPair where OutputValue: Equatable {
	
	public func contains(value: OutputValue) -> SignalPair<InputValue, Input, Bool, Signal<Bool>> {
		return next { $0.contains(value: value) }
	}
}

extension SignalPair {
	
	public func defaultIfEmpty(value: OutputValue) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.defaultIfEmpty(value: value) }
	}
	
	public func switchIfEmpty(alternate: Signal<OutputValue>) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.switchIfEmpty(alternate: alternate) }
	}
}

extension SignalPair where OutputValue: Equatable {
	
	public func sequenceEqual(to: Signal<OutputValue>) -> SignalPair<InputValue, Input, Bool, Signal<Bool>> {
		return next { $0.sequenceEqual(to: to) }
	}
}

extension SignalPair {
	
	public func skipUntil<U>(_ other: Signal<U>) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.skipUntil(other) }
	}
	
	public func skipWhile(context: Exec = .direct, condition: @escaping (OutputValue) -> Bool) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.skipWhile(context: context, condition: condition) }
	}
	
	public func skipWhile<U>(initialState initial: U, context: Exec = .direct, condition: @escaping (inout U, OutputValue) -> Bool) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.skipWhile(initialState: initial, context: context, condition: condition) }
	}
	
	public func takeUntil<U>(_ other: Signal<U>) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.takeUntil(other) }
	}
	
	public func takeWhile(context: Exec = .direct, condition: @escaping (OutputValue) -> Bool) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.takeWhile(context: context, condition: condition) }
	}
	
	public func takeWhile<U>(initialState initial: U, context: Exec = .direct, condition: @escaping (inout U, OutputValue) -> Bool) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.takeWhile(initialState: initial, context: context, condition: condition) }
	}
	
	public func foldAndFinalize<U, V>(_ initial: V, context: Exec = .direct, finalize: @escaping (V) -> U?, fold: @escaping (V, OutputValue) -> V) -> SignalPair<InputValue, Input, U, Signal<U>> {
		return next { $0.foldAndFinalize(initial, context: context, finalize: finalize, fold: fold) }
	}
}

extension SignalPair where OutputValue: BinaryInteger {
	
	public func average() -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.average() }
	}
}

extension SignalPair {
	
	public func concat(_ other: Signal<OutputValue>) -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.concat(other) }
	}
	
	public func count() -> SignalPair<InputValue, Input, Int, Signal<Int>> {
		return next { $0.count() }
	}
}

extension SignalPair where OutputValue: Comparable {
	
	public func min() -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.min() }
	}
	
	public func max() -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.max() }
	}
}

extension SignalPair {
	public func reduce<U>(_ initial: U, context: Exec = .direct, fold: @escaping (U, OutputValue) -> U) -> SignalPair<InputValue, Input, U, Signal<U>> {
		return next { $0.reduce(initial, context: context, fold: fold) }
	}
}

extension SignalPair where OutputValue: Numeric {
	public func sum() -> SignalPair<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.sum() }
	}
}

// Implementation of Signal.swift
extension SignalInput {
	public static func subscribeAndKeepAlive(context: Exec = .direct, handler: @escaping (Result<Value>) -> Bool) -> SignalInput<Value> {
		return Channel().subscribeAndKeepAlive(context: context, handler: handler)
	}
	
	public static func join(to: SignalInput<Value>) -> SignalInput<Value> {
		return Channel().join(to: to)
	}
	
	public static func subscribeValuesAndKeepAlive(context: Exec = .direct, handler: @escaping (Value) -> Bool) -> SignalInput<Value> {
		return Channel().subscribeValuesAndKeepAlive(context: context, handler: handler)
	}
	
	public static func join(to: SignalMergedInput<Value>, closePropagation: SignalClosePropagation = .none, removeOnDeactivate: Bool = false) -> SignalInput<Value> {
		return Channel().join(to: to, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate)
	}
	
	public static func join(to: SignalMultiInput<Value>) -> SignalInput<Value> {
		return Channel().join(to: to)
	}
}

