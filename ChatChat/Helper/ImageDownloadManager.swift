//
//  ImageDownloadManager.swift
//  ChatChat
//
//  Created by Kittisak Phetrungnapha on 2/20/2560 BE.
//  Copyright © 2560 Razeware LLC. All rights reserved.
//

import Foundation
import Kingfisher

struct ImageDownloadManager {
    
    static let shared = ImageDownloadManager()
    
    private init() {}
    
    // MARK: - Public method
    
    func fetchImage(with imageUrl: String, completion: @escaping (UIImage?) -> Void) {
        // Check if cache is existing.
        if checkImageCache(with: imageUrl) {
            fetchImageFromCache(with: imageUrl, completion: { (image: Image?) in
                completion(image)
            })
            return
        }
        
        // Download image from url.
        download(from: imageUrl) { (image: Image?) in
            if let image = image {
                // Save image to cache
                self.saveImageToDisk(with: image, key: imageUrl)
                
                completion(image)
                return
            }
            completion(nil)
        }
    }
    
    // MARK: - Private method
    
    private func checkImageCache(with key: String) -> Bool {
        return ImageCache.default.isImageCached(forKey: key).cached
    }
    
    private func fetchImageFromCache(with key: String, completion: @escaping (Image?) -> Void) {
        ImageCache.default.retrieveImage(forKey: key, options: nil) {
            image, cacheType in
            completion(image)
        }
    }
    
    private func download(from imageUrl: String, completion: @escaping (Image?) -> Void) {
        ImageDownloader.default.downloadImage(with: URL(string: imageUrl)!, options: [], progressBlock: nil) {
            (image, error, url, data) in
            completion(image)
        }
    }
    
    private func saveImageToDisk(with image: Image, key: String) {
        ImageCache.default.store(image, forKey: key)
    }
    
}
