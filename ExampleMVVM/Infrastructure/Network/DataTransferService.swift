//
//  DataTransfer.swift
//  ExampleMVVM
//
//  Created by Oleh Kudinov on 01.10.18.
//

import Foundation

public enum DataTransferError: Error {
    case noResponse
    case parsing
    case networkFailure(NetworkError)
    case resolvedNetworkFailure(Error)
}
extension DataTransferError: ConnectionError {
    public var isInternetConnectionError: Bool {
        guard case let DataTransferError.networkFailure(networkError) = self,
            case .notConnected = networkError else {
                return false
        }
        return true
    }
}

public protocol DataTransferService {
    @discardableResult
    func request<T: Decodable, E: ResponseRequestable>(with endpoint: E,
                                                       completion: @escaping (Result<T, Error>) -> Void) -> NetworkCancellable? where E.Response == T
}

public protocol DataTransferErrorResolver {
    func resolve(response: NetworkServiceResponse?, error: NetworkError) -> Error?
}

public protocol ResponseDecoder {
    func decode<T: Decodable>(_ data: Data) throws -> T
}

public protocol DataTransferErrorLogger {
    func log(error: Error)
}

public final class DefaultDataTransferService {
    
    private let networkService: NetworkService
    private let responseDecoder: ResponseDecoder
    private let errorResolver: DataTransferErrorResolver
    private let errorLogger: DataTransferErrorLogger
    
    public init(with networkService: NetworkService,
                responseDecoder: ResponseDecoder = JSONResponseDecoder(),
                errorResolver: DataTransferErrorResolver = DefaultDataTransferErrorResolver(),
                errorLogger: DataTransferErrorLogger = DefaultDataTransferErrorLogger()) {
        self.networkService = networkService
        self.responseDecoder = responseDecoder
        self.errorResolver = errorResolver
        self.errorLogger = errorLogger
    }
}

extension DefaultDataTransferService: DataTransferService {
    
    public func request<T: Decodable, E: ResponseRequestable>(with endpoint: E,
                                                              completion: @escaping (Result<T, Error>) -> Void) -> NetworkCancellable? where E.Response == T {
        
        return self.networkService.request(endpoint: endpoint) { result in
            switch result {
            case .success(let response):
                do {
                    let result: T = try self.parse(data: response.data)
                    DispatchQueue.main.async { completion(Result.success(result)) }
                } catch {
                    DispatchQueue.main.async { completion(Result.failure(error)) }
                }
            case .failure(let error):
                self.errorLogger.log(error: error)
                let error = self.hande(error: error)
                DispatchQueue.main.async { completion(Result.failure(error)) }
            }
        }
    }
    
    private func parse<T: Decodable>(data: Data?) throws -> T {
        
        if T.self is Data.Type, let data = data as? T {
            return data
        }
        
        guard let data = data else {
            throw DataTransferError.noResponse
        }
        do {
            return try self.responseDecoder.decode(data)
        } catch {
            self.errorLogger.log(error: error)
            throw DataTransferError.parsing
        }
    }
    
    private func hande(error: NetworkError) -> DataTransferError {
        
        if case let NetworkError.error(_, response) = error,
            let resolvedError = self.errorResolver.resolve(response: response,
                                                           error: error), !(resolvedError is NetworkError) {
            return DataTransferError.resolvedNetworkFailure(resolvedError)
        } else {
            return DataTransferError.networkFailure(error)
        }
    }
}

// MARK: - Logger
final public class DefaultDataTransferErrorLogger: DataTransferErrorLogger {
    public init() { }
    
    public func log(error: Error) {
        #if DEBUG
        print("-------------")
        print("error: \(error)")
        #endif
    }
}

// MARK: - Error Resolver
public class DefaultDataTransferErrorResolver: DataTransferErrorResolver {
    public init() { }
    public func resolve(response: NetworkServiceResponse?, error: NetworkError) -> Error? {
        return nil
    }
}

// MARK: - JSON Response Decoder
public class JSONResponseDecoder: ResponseDecoder {
    private let jsonDecoder = JSONDecoder()
    public init() { }
    public func decode<T: Decodable>(_ data: Data) throws -> T {
        return try jsonDecoder.decode(T.self, from: data)
    }
}
