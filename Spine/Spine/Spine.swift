//
//  Resource.swift
//  Spine
//
//  Created by Ward van Teijlingen on 21-08-14.
//  Copyright (c) 2014 Ward van Teijlingen. All rights reserved.
//

import Foundation
import SwiftyJSON
import BrightFutures

let SPINE_ERROR_DOMAIN = "com.wardvanteijlingen.Spine"

public class Spine {

	public class var sharedInstance: Spine {
        struct Singleton {
            static let instance = Spine()
        }

        return Singleton.instance
    }

	public var endPoint: String
	private let serializer = Serializer()
	private let HTTPClient: HTTPClientProtocol = AlamofireClient()

	public init() {
		self.endPoint = ""
	}

	public init(endPoint: String) {
		self.endPoint = endPoint
	}
	
	public init(endPoint: String, HTTPClient: HTTPClientProtocol) {
		self.endPoint = endPoint
		self.HTTPClient = HTTPClient
	}
	
	
	// MARK: Mapping
	
	/**
	Registers the given class as a resource class.
	
	:param: type The class type.
	*/
	public func registerType(type: Resource.Type) {
		self.serializer.registerClass(type)
	}
	
	
	// MARK: Routing
	
	private func URLForCollectionOfResource(resource: Resource) -> String {
		return "\(self.endPoint)/\(resource.resourceType)"
	}
	
	private func URLForResource(resource: Resource) -> String {
		if let resourceLocation = resource.resourceLocation {
			return resourceLocation
		}
		
		assert(resource.resourceID != nil, "Resource does not have an href, nor a resource ID.")
		
		return "\(self.endPoint)/\(resource.resourceType)/\(resource.resourceID!)"
	}
	
	private func URLForQuery(query: Query) -> String {
		return query.URLRelativeToURL(self.endPoint)
	}


	// MARK: Fetching

	/**
	 Fetches a resource with the given type and ID.

	 :param: resourceType The type of resource to fetch. Must be plural.
	 :param: ID           The ID of the resource to fetch.
	 :param: success      Function to call after success.
	 :param: failure      Function to call after failure.
	 */
	public func fetchResourceWithType(resourceType: String, ID: String) -> Future<Resource> {
		let promise = Promise<Resource>()
		
		let query = Query(resourceType: resourceType, resourceIDs: [ID])
		
		self.fetchResourcesForQuery(query).onSuccess { resources in
			promise.success(resources.first!)
		}.onFailure { error in
			promise.error(error)
		}
		
		return promise.future
	}

	/**
	Fetches resources related to the given resource by a given relationship
	
	:param: relationship The name of the relationship.
	:param: resource     The resource that contains the relationship.
	
	:returns: Future of an array of resources.
	*/
	public func fetchResourcesForRelationship(relationship: String, ofResource resource: Resource) -> Future<[Resource]> {
		let query = Query(resource: resource, relationship: relationship)
		return self.fetchResourcesForQuery(query)
	}

	/**
	Fetches resources by executing the given query.
	
	:param: query The query to execute.
	
	:returns: Future of an array of resources.
	*/
	public func fetchResourcesForQuery(query: Query) -> Future<[Resource]> {
		let promise = Promise<[Resource]>()
		
		let URLString = self.URLForQuery(query)
		
		self.HTTPClient.get(URLString, callback: { responseStatus, responseData, error in
			if let error = error {
				promise.error(error)
				
			} else if let JSONData = responseData {
				let JSON = JSONValue(JSONData as NSData!)
				
				if 200 ... 299 ~= responseStatus! {
					let mappedResourcesStore = self.serializer.deserializeData(JSON)
					promise.success(mappedResourcesStore.resourcesWithName(query.resourceType))
				} else {
					let error = self.serializer.deserializeError(JSON, withResonseStatus: responseStatus!)
					promise.error(error)
				}
			}
		})
		
		return promise.future
	}


	// MARK: Saving

	/**
	Saves a resource to the server.
	This will also relate and unrelate any pending related and unrelated resource.
	Related resources will not be saved automatically. You must ensure that related resources are saved before saving any parent resource.
	
	:param: resource The resource to save.
	
	:returns: Future of the resource saved.
	*/
	public func saveResource(resource: Resource) -> Future<Resource> {
		let promise = Promise<Resource>()
		
		let parameters = self.serializer.serializeResources([resource])

		let callback: (Int?, NSData?, NSError?) -> Void = { responseStatus, responseData, error in
			if let error = error {
				promise.error(error)
				return
			}
			
			// Map the response back onto the resource
			if let JSONData = responseData {
				let JSON = JSONValue(JSONData)
				let store = ResourceStore(resources: [resource])
				let mappedResourcesStore = self.serializer.deserializeData(JSON, usingStore: store)
			}
			
			promise.success(resource)
		}
		
		// Create resource
		if resource.resourceID == nil {
			resource.resourceID = NSUUID().UUIDString
			self.HTTPClient.post(self.URLForCollectionOfResource(resource), json: parameters, callback: callback)

		// Update resource
		} else {
			self.HTTPClient.put(self.URLForResource(resource), json: parameters, callback: callback)
		}
		
		return promise.future
	}
	

	// MARK: Deleting

	/**
	Deletes the resource from the server.
	This will fire a DELETE request to an URL of the form: /{resourceType}/{id}.
	
	:param: resource The resource to delete.
	
	:returns: Void future.
	*/
	public func deleteResource(resource: Resource) -> Future<Void> {
		let promise = Promise<Void>()
		
		let URLString = self.URLForResource(resource)
		
		self.HTTPClient.delete(URLString, callback: { responseStatus, responseData, error in
			if let error = error {
				promise.error(error)
			} else {
				promise.success()
			}
		})
		
		return promise.future
	}
}