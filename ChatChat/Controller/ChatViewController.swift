/*
 * Copyright (c) 2015 Razeware LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

import UIKit
import JSQMessagesViewController
import FirebaseDatabase
import FirebaseStorage
import Photos
import GoogleSignIn
import FirebaseAuth

final class ChatViewController: JSQMessagesViewController {
    
    // MARK: Properties
    private var messages = [JSQMessage]()
    private var photoMessageMap = [String: JSQPhotoMediaItem]()
    private var avatars = [String: JSQMessagesAvatarImage]()
    private let imageURLNotSetKey = "NOTSET"
    private let messageQueryLimit: UInt = 25
    var avatarString: String!
    
    private lazy var outgoingBubbleImageView: JSQMessagesBubbleImage = self.setupOutgoingBubble()
    private lazy var incomingBubbleImageView: JSQMessagesBubbleImage = self.setupIncomingBubble()
    
    private lazy var messageRef: FIRDatabaseReference = FIRDatabase.database().reference().child("messages")
    fileprivate lazy var storageRef: FIRStorageReference = FIRStorage.storage().reference(forURL: "gs://fir-devday.appspot.com")
    
    private var newMessageRefHandle: FIRDatabaseHandle?
    private var updatedMessageRefHandle: FIRDatabaseHandle?
    
    // MARK: View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupLogOutButton()
        observeMessages()
    }
    
    deinit {
        // TODO: - Unregister Firebase listeners.
        if let refHandle = newMessageRefHandle {
            messageRef.removeObserver(withHandle: refHandle)
        }
        if let refHandle = updatedMessageRefHandle {
            messageRef.removeObserver(withHandle: refHandle)
        }
    }
    
    // MARK: -
    private func setupLogOutButton() {
        let logOutButton = UIBarButtonItem(title: "Sign out", style: .plain, target: self, action: #selector(signOut))
        self.navigationItem.leftBarButtonItem = logOutButton
    }
    
    func signOut() {
        // TODO: - Firebase Sign out
        do {
            try FIRAuth.auth()?.signOut()
        } catch let signOutError as NSError {
            print ("Error Firebase signing out: \(signOutError)")
        }
        
        // TODO: Google Sign out
        GIDSignIn.sharedInstance().signOut()
        
        let loginVC = self.storyboard?.instantiateViewController(withIdentifier: "LoginViewController")
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        appDelegate.window?.rootViewController = loginVC
    }
    
    // MARK: - Collection view data source (and related) methods
    override func collectionView(_ collectionView: JSQMessagesCollectionView!, messageDataForItemAt indexPath: IndexPath!) -> JSQMessageData! {
        return messages[indexPath.item]
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return messages.count
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView!, messageBubbleImageDataForItemAt indexPath: IndexPath!) -> JSQMessageBubbleImageDataSource! {
        let message = messages[indexPath.item]
        if message.senderId == self.senderId {
            return outgoingBubbleImageView
        } else {
            return incomingBubbleImageView
        }
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView!, avatarImageDataForItemAt indexPath: IndexPath!) -> JSQMessageAvatarImageDataSource! {
        let message = messages[indexPath.item]
        return self.avatars[message.senderId]
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = super.collectionView(collectionView, cellForItemAt: indexPath) as! JSQMessagesCollectionViewCell
        let message = messages[indexPath.item]
        
        if message.senderId == self.senderId {
            cell.textView?.textColor = UIColor.white
        } else {
            cell.textView?.textColor = UIColor.black
        }
        
        return cell
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView!, attributedTextForMessageBubbleTopLabelAt indexPath: IndexPath!) -> NSAttributedString! {
        let message = messages[indexPath.item]
        return NSAttributedString(string: message.senderDisplayName)
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView!, layout collectionViewLayout: JSQMessagesCollectionViewFlowLayout!, heightForMessageBubbleTopLabelAt indexPath: IndexPath!) -> CGFloat {
        return kJSQMessagesCollectionViewCellLabelHeightDefault
    }
    
    // MARK: - Firebase related methods
    override func didPressSend(_ button: UIButton!, withMessageText text: String!, senderId: String!, senderDisplayName: String!, date: Date!) {
        // TODO: - Sent text message to Firebase
        let itemRef = messageRef.childByAutoId()
        let messageItem = [
            "avatar": avatarString,
            "data": text,
            "type": "text",
            "username": senderDisplayName,
            "senderId": senderId
        ]
        
        itemRef.setValue(messageItem)
        JSQSystemSoundPlayer.jsq_playMessageSentSound()
        finishSendingMessage()
    }
    
    private func observeMessages() {
        let messageQuery = messageRef.queryLimited(toLast: messageQueryLimit)
        observeAddNewMessage(with: messageQuery)
        observeUpdateMessage(with: messageQuery)
    }
    
    private func observeAddNewMessage(with messageQuery: FIRDatabaseQuery) {
        // TODO: - observe childAdded
        newMessageRefHandle = messageQuery.observe(.childAdded, with: { (snapshot) -> Void in
            let messageData = snapshot.value as! Dictionary<String, String>
            
            if let type = messageData["type"] as String!,
                type == "text",
                let id = messageData["senderId"] as String!,
                let displayName = messageData["username"] as String!,
                let avatar = messageData["avatar"] as String!,
                let text = messageData["data"] as String!,
                text.characters.count > 0 {
                
                self.addMessage(withId: id, name: displayName, text: text)
                self.downloadCircleAvatar(with: avatar, avatarImage: self.prepareAvatarImage(with: id))
                self.finishReceivingMessage()
            }
                
            else if let type = messageData["type"] as String!,
                type == "image",
                let id = messageData["senderId"] as String!,
                let displayName = messageData["username"] as String!,
                let photoURL = messageData["data"] as String!,
                let avatar = messageData["avatar"] as String!,
                photoURL.characters.count > 0 {
                
                if let mediaItem = JSQPhotoMediaItem(maskAsOutgoing: self.senderId == id) {
                    self.addPhotoMessage(with: id, displayName: displayName, key: snapshot.key, mediaItem: mediaItem)
                    self.downloadCircleAvatar(with: avatar, avatarImage: self.prepareAvatarImage(with: id))
                    
                    if photoURL.hasPrefix("http://") || photoURL.hasPrefix("https://") {
                        self.fetchImageDataAtURL(photoURL, forMediaItem: mediaItem, clearsPhotoMessageMapOnSuccessForKey: nil)
                    }
                }
            }
                
            else {
                print("Error! Could not decode message data")
            }
        })
    }
    
    private func observeUpdateMessage(with messageQuery: FIRDatabaseQuery) {
        // TODO: - observe childChanged
        updatedMessageRefHandle = messageRef.observe(.childChanged, with: { (snapshot) in
            let key = snapshot.key
            let messageData = snapshot.value as! Dictionary<String, String>
            
            if let type = messageData["type"] as String!,
                type == "image",
                let photoURL = messageData["data"] as String!,
                photoURL.characters.count > 0 {
                
                // The photo has been updated.
                if let mediaItem = self.photoMessageMap[key] {
                    self.fetchImageDataAtURL(photoURL, forMediaItem: mediaItem, clearsPhotoMessageMapOnSuccessForKey: key)
                }
            }
        })
    }
    
    private func fetchImageDataAtURL(_ photoURL: String, forMediaItem mediaItem: JSQPhotoMediaItem, clearsPhotoMessageMapOnSuccessForKey key: String?) {
        
        ImageDownloadManager.shared.fetchImage(with: photoURL) { (image: UIImage?) in
            if let image = image {
                mediaItem.image = image
            }
            
            self.finishReceivingMessage()
            guard let key = key else { return }
            self.photoMessageMap.removeValue(forKey: key)
        }
    }
    
    // MARK: - UI and User Interaction
    private func setupOutgoingBubble() -> JSQMessagesBubbleImage {
        let bubbleImageFactory = JSQMessagesBubbleImageFactory()
        return bubbleImageFactory!.outgoingMessagesBubbleImage(with: UIColor.orange.withAlphaComponent(0.8))
    }
    
    private func setupIncomingBubble() -> JSQMessagesBubbleImage {
        let bubbleImageFactory = JSQMessagesBubbleImageFactory()
        return bubbleImageFactory!.incomingMessagesBubbleImage(with: UIColor.jsq_messageBubbleLightGray())
    }
    
    private func addMessage(withId id: String, name: String, text: String) {
        if let message = JSQMessage(senderId: id, displayName: name, text: text) {
            messages.append(message)
        }
    }
    
    private func addPhotoMessage(with id: String, displayName: String, key: String, mediaItem: JSQPhotoMediaItem) {
        if let message = JSQMessage(senderId: id, displayName: displayName, media: mediaItem) {
            messages.append(message)
            
            if (mediaItem.image == nil) {
                photoMessageMap[key] = mediaItem
            }
            
            collectionView.reloadData()
        }
    }
    
    fileprivate func sendPhotoMessage() -> String? {
        // TODO: - Sent photo message to Firebase.
        let itemRef = messageRef.childByAutoId()
        
        let messageItem = [
            "avatar": avatarString,
            "data": imageURLNotSetKey,
            "type": "image",
            "username": senderDisplayName,
            "senderId": senderId
        ]
        
        itemRef.setValue(messageItem)
        JSQSystemSoundPlayer.jsq_playMessageSentSound()
        finishSendingMessage()
        
        return itemRef.key
    }
    
    fileprivate func setImageURL(_ url: String, forPhotoMessageWithKey key: String) {
        // TODO: - Update existing image when generate image url successfully.
        let itemRef = messageRef.child(key)
        itemRef.updateChildValues(["data": url])
    }
    
    private func downloadCircleAvatar(with imageUrl: String, avatarImage: JSQMessagesAvatarImage) {
        ImageDownloadManager.shared.fetchImage(with: imageUrl, completion: { (image: UIImage?) in
            if let image = image {
                avatarImage.avatarImage = JSQMessagesAvatarImageFactory.circularAvatarImage(image, withDiameter: UInt(kJSQMessagesCollectionViewAvatarSizeDefault))
            }
        })
    }
    
    private func prepareAvatarImage(with id: String) -> JSQMessagesAvatarImage! {
        if (self.avatars[id] == nil) {
            let avartarImage = JSQMessagesAvatarImageFactory.avatarImage(withUserInitials: "F", backgroundColor: UIColor.groupTableViewBackground, textColor: UIColor.lightGray, font: UIFont.systemFont(ofSize: 17), diameter: UInt(kJSQMessagesCollectionViewAvatarSizeDefault))
            self.avatars[id] = avartarImage
        }
        
        return self.avatars[id]
    }
    
    override func didPressAccessoryButton(_ sender: UIButton) {
        let picker = UIImagePickerController()
        picker.delegate = self
        
        // physical device
        if UIImagePickerController.isSourceTypeAvailable(UIImagePickerControllerSourceType.camera) {
            let alert = UIAlertController.init(title: "Select Image Source", message: nil, preferredStyle: .actionSheet)
            let cameraAction = UIAlertAction.init(title: "Camera", style: .default, handler: { action in
                picker.sourceType = .camera
                self.present(picker, animated: true, completion:nil)
            })
            let photoLibraryAction = UIAlertAction.init(title: "Photo Library", style: .default, handler: { action in
                picker.sourceType = .photoLibrary
                self.present(picker, animated: true, completion:nil)
            })
            let cancelAction = UIAlertAction.init(title: "Cancel", style: .cancel, handler: nil)
            
            alert.addAction(cameraAction)
            alert.addAction(photoLibraryAction)
            alert.addAction(cancelAction)
            
            self.present(alert, animated: true, completion: nil)
        }
            
        // simulator
        else {
            picker.sourceType = .photoLibrary
            self.present(picker, animated: true, completion:nil)
        }
    }
    
}

// MARK: Image Picker Delegate
extension ChatViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [String : Any]) {
        picker.dismiss(animated: true, completion:nil)
        
        guard let photoReferenceUrl = info[UIImagePickerControllerReferenceURL] as? URL else {
            // Handle picking a Photo from the Camera (physical device)
            guard let image = info[UIImagePickerControllerOriginalImage] as? UIImage else { return }
            
            if let key = sendPhotoMessage() {
                guard let imageData = UIImageJPEGRepresentation(image, 1.0) else { return }
                
                let imagePath = "\(key).jpg"
                let metadata = FIRStorageMetadata()
                metadata.contentType = "image/jpeg"
                
                // TODO: - Upload image to storage.
                storageRef.child(imagePath).put(imageData, metadata: metadata) { (metadata, error) in
                    self.handleImageResult(with: metadata, error: error, key: key)
                }
            }
            
            return
        }
        
        // Handle picking a Photo from the Photo Library
        let assets = PHAsset.fetchAssets(withALAssetURLs: [photoReferenceUrl], options: nil)
        guard let asset = assets.firstObject else { return }
        guard let key = sendPhotoMessage() else { return }
        
        if TARGET_OS_SIMULATOR != 0 {
            asset.requestContentEditingInput(with: nil, completionHandler: { (contentEditingInput, info) in
                guard let imageFileURL = contentEditingInput?.fullSizeImageURL else { return }
                
                let path = "\(key).jpg"
                
                // TODO: - Upload image to storage.
                self.storageRef.child(path).putFile(imageFileURL, metadata: nil) { (metadata, error) in
                    self.handleImageResult(with: metadata, error: error, key: key)
                }
            })
        }
        else {
            let manager = PHImageManager.default()
            manager.requestImage(for: asset, targetSize: CGSize(width: 640.0, height: 960.0), contentMode: .aspectFit, options: nil, resultHandler: { (result, info) -> Void in
                
                guard let result = result else { return }
                
                let path = "\(key).jpg"
                guard let data = UIImageJPEGRepresentation(result, 1.0) else { return }
                
                let metadata = FIRStorageMetadata()
                metadata.contentType = "image/jpeg"
                
                // TODO: - Upload image to storage.
                self.storageRef.child(path).put(data, metadata: metadata, completion: { (metadata, error) in
                    self.handleImageResult(with: metadata, error: error, key: key)
                })
            })
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion:nil)
    }
    
    private func handleImageResult(with metadata: FIRStorageMetadata?, error: Error?, key: String) {
        if let error = error {
            print("Error uploading photo: \(error.localizedDescription)")
            return
        }
        guard let downloadUrl = metadata?.downloadURL()?.absoluteString else { return }
        
        self.setImageURL(downloadUrl, forPhotoMessageWithKey: key)
    }
    
}
