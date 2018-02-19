//
//  DelegatingHTTPNetworkTransport.swift
//  Apollo
//
//  Created by Michał Lisok on 16.02.2018.
//  Copyright © 2018 Apollo GraphQL. All rights reserved.
//

import Foundation

/// A network transport that uses HTTP POST requests to send GraphQL operations to a server, and that uses `URLSession` as the networking implementation.
public class DelegatingHTTPNetworkTransport: NetworkTransport {
    let url: URL
    public let session: URLSession
    let serializationFormat = JSONSerializationFormat.self
    
    /// Creates a network transport with the specified server URL and session configuration.
    ///
    /// - Parameters:
    ///   - url: The URL of a GraphQL server to connect to.
    ///   - configuration: A session configuration used to configure the session. Defaults to `URLSessionConfiguration.default`.
    ///   - sendOperationIdentifiers: Whether to send operation identifiers rather than full operation text, for use with servers that support query persistence. Defaults to false.
    public init(url: URL, configuration: URLSessionConfiguration = URLSessionConfiguration.default, sendOperationIdentifiers: Bool = false) {
        self.url = url
        self.session = URLSession(configuration: configuration)
        self.sendOperationIdentifiers = sendOperationIdentifiers
    }
    
    /// Send a GraphQL operation to a server and return a response.
    ///
    /// - Parameters:
    ///   - operation: The operation to send.
    ///   - completionHandler: A closure to call when a request completes.
    ///   - response: The response received from the server, or `nil` if an error occurred.
    ///   - error: An error that indicates why a request failed, or `nil` if the request was succesful.
    /// - Returns: An object that can be used to cancel an in progress request.
    public func send<Operation>(operation: Operation, completionHandler: @escaping (_ response: GraphQLResponse<Operation>?, _ error: Error?) -> Void) -> Cancellable {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = requestBody(for: operation)
        request.httpBody = try! serializationFormat.serialize(value: body)
        
        let task = session.dataTask(with: request) { (data: Data?, response: URLResponse?, error: Error?) in
            if error != nil {
                completionHandler(nil, error)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                fatalError("Response should be an HTTPURLResponse")
            }
            
            if (!httpResponse.isSuccessful) {
                completionHandler(nil, GraphQLHTTPResponseError(body: data, response: httpResponse, kind: .errorResponse))
                return
            }
            
            guard let data = data else {
                completionHandler(nil, GraphQLHTTPResponseError(body: nil, response: httpResponse, kind: .invalidResponse))
                return
            }
            
            do {
                guard let body =  try self.serializationFormat.deserialize(data: data) as? JSONObject else {
                    throw GraphQLHTTPResponseError(body: data, response: httpResponse, kind: .invalidResponse)
                }
                let response = GraphQLResponse(operation: operation, body: body)
                completionHandler(response, nil)
            } catch {
                completionHandler(nil, error)
            }
        }
        
        task.resume()
        
        return task
    }
    
    private let sendOperationIdentifiers: Bool
    
    private func requestBody<Operation: GraphQLOperation>(for operation: Operation) -> GraphQLMap {
        if sendOperationIdentifiers {
            guard let operationIdentifier = type(of: operation).operationIdentifier else {
                preconditionFailure("To send operation identifiers, Apollo types must be generated with operationIdentifiers")
            }
            return ["id": operationIdentifier, "variables": operation.variables]
        }
        return ["query": type(of: operation).requestString, "variables": operation.variables]
    }
}
