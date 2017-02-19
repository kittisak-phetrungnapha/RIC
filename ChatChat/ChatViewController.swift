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
import FirebaseAuth
import FirebaseStorage
import Photos
import GoogleSignIn

final class ChatViewController: JSQMessagesViewController {
    
    // MARK: Properties
    var messages = [JSQMessage]()
    
    lazy var outgoingBubbleImageView: JSQMessagesBubbleImage = self.setupOutgoingBubble()
    lazy var incomingBubbleImageView: JSQMessagesBubbleImage = self.setupIncomingBubble()
    private lazy var messageRef: FIRDatabaseReference = FIRDatabase.database().reference().child("messages")
    private var newMessageRefHandle: FIRDatabaseHandle?
    
    lazy var storageRef: FIRStorageReference = FIRStorage.storage().reference(forURL: "gs://fir-devday.appspot.com")
    private let imageURLNotSetKey = "NOTSET"
    private var photoMessageMap = [String: JSQPhotoMediaItem]()
    private var updatedMessageRefHandle: FIRDatabaseHandle?
    
    private let username = FIRAuth.auth()?.currentUser?.displayName ?? "Kittisak Phetrungnapha"
    private let avatar = FIRAuth.auth()?.currentUser?.photoURL?.absoluteString ?? "https://lh5.googleusercontent.com/-YpXDnaI_YM0/AAAAAAAAAAI/AAAAAAAAB30/rvs3MJ_YPOE/s96-c/photo.jpg"
    
    // MARK: View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "Firebase"
        setupLogOutButton()
        
        self.senderId = FIRAuth.auth()?.currentUser?.uid
        
        observeMessages()
    }
    
    deinit {
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
        let firebaseAuth = FIRAuth.auth()
        do {
            try firebaseAuth?.signOut()
        } catch let signOutError as NSError {
            print ("Error Firebase signing out: %@", signOutError)
        }
        
        GIDSignIn.sharedInstance().signOut()
        
        let loginVC = self.storyboard?.instantiateViewController(withIdentifier: "LoginViewController")
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        appDelegate.window?.rootViewController = loginVC
    }
    
    // MARK: Collection view data source (and related) methods
    override func collectionView(_ collectionView: JSQMessagesCollectionView!, messageDataForItemAt indexPath: IndexPath!) -> JSQMessageData! {
        return messages[indexPath.item]
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return messages.count
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView!, messageBubbleImageDataForItemAt indexPath: IndexPath!) -> JSQMessageBubbleImageDataSource! {
        let message = messages[indexPath.item]
        if message.senderId == username {
            return outgoingBubbleImageView
        } else {
            return incomingBubbleImageView
        }
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView!, avatarImageDataForItemAt indexPath: IndexPath!) -> JSQMessageAvatarImageDataSource! {
        
        return JSQMessagesAvatarImageFactory.avatarImage(with: UIImage(named: "football.png"), diameter: UInt(kJSQMessagesCollectionViewAvatarSizeDefault))
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView!, attributedTextForCellTopLabelAt indexPath: IndexPath!) -> NSAttributedString! {
        let message = messages[indexPath.item]
        return NSAttributedString(string: message.senderDisplayName)
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView!, attributedTextForCellBottomLabelAt indexPath: IndexPath!) -> NSAttributedString! {
        return nil
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = super.collectionView(collectionView, cellForItemAt: indexPath) as! JSQMessagesCollectionViewCell
        let message = messages[indexPath.item]
        
        if message.senderId == username {
            cell.textView?.textColor = UIColor.white
        } else {
            cell.textView?.textColor = UIColor.black
        }
        return cell
    }
    
    // MARK: Firebase related methods
    override func didPressSend(_ button: UIButton!, withMessageText text: String!, senderId: String!, senderDisplayName: String!, date: Date!) {
        let itemRef = messageRef.childByAutoId()
        let messageItem = [
            "avatar": avatar,
            "data": text,
            "type": "text",
            "username": username
            ]
        
        itemRef.setValue(messageItem)
        JSQSystemSoundPlayer.jsq_playMessageSentSound()
        finishSendingMessage()
    }
    
    private func observeMessages() {
        let messageQuery = messageRef.queryLimited(toLast: 25)
        
        // We can use the observe method to listen for new
        // messages being written to the Firebase DB
        newMessageRefHandle = messageQuery.observe(.childAdded, with: { (snapshot) -> Void in
            let messageData = snapshot.value as! Dictionary<String, String>
            
            if let type = messageData["type"] as String!, type == "text", let username = messageData["username"] as String!, let text = messageData["data"] as String!, text.characters.count > 0 {
                self.addMessage(withId: username, name: "Top", text: text)
                self.finishReceivingMessage()
            }
                
            else if let type = messageData["type"] as String!, type == "image",
                let photoURL = messageData["data"] as String!,
                let username = messageData["username"] as String! {
                
                if let mediaItem = JSQPhotoMediaItem(maskAsOutgoing: false) {
                    self.addPhotoMessage(withId: username, key: snapshot.key, mediaItem: mediaItem)
                    
                    if photoURL.hasPrefix("gs://") {
                        self.fetchImageDataAtURL(photoURL, forMediaItem: mediaItem, clearsPhotoMessageMapOnSuccessForKey: nil)
                    }
                }
                
//                if let mediaItem = JSQPhotoMediaItem(maskAsOutgoing: id == self.senderId) {
//                    self.addPhotoMessage(withId: id, key: snapshot.key, mediaItem: mediaItem)
//                    
//                    if photoURL.hasPrefix("gs://") {
//                        self.fetchImageDataAtURL(photoURL, forMediaItem: mediaItem, clearsPhotoMessageMapOnSuccessForKey: nil)
//                    }
//                }
            }
                
            else {
                print("Error! Could not decode message data")
            }
        })
        
        // We can also use the observer method to listen for
        // changes to existing messages.
        // We use this to be notified when a photo has been stored
        // to the Firebase Storage, so we can update the message data
        updatedMessageRefHandle = messageRef.observe(.childChanged, with: { (snapshot) in
            let key = snapshot.key
            let messageData = snapshot.value as! Dictionary<String, String>
            
            if let photoURL = messageData["data"] as String! {
                // The photo has been updated.
                if let mediaItem = self.photoMessageMap[key] {
                    self.fetchImageDataAtURL(photoURL, forMediaItem: mediaItem, clearsPhotoMessageMapOnSuccessForKey: key)
                }
            }
        })
    }
    
    private func fetchImageDataAtURL(_ photoURL: String, forMediaItem mediaItem: JSQPhotoMediaItem, clearsPhotoMessageMapOnSuccessForKey key: String?) {
        let storageRef = FIRStorage.storage().reference(forURL: photoURL)
        
        storageRef.data(withMaxSize: INT64_MAX) { (data, error) in
            if let error = error {
                print("Error downloading image data: \(error.localizedDescription)")
                return
            }
            
            storageRef.metadata(completion: { (metadata, metadataErr) in
                if let error = metadataErr {
                    print("Error downloading metadata: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else { return }
                if (metadata?.contentType == "image/gif") {
                    mediaItem.image = UIImage.gifWithData(data)
                } else {
                    mediaItem.image = UIImage.init(data: data)
                }
                self.collectionView.reloadData()
                
                guard let key = key else { return }
                self.photoMessageMap.removeValue(forKey: key)
            })
        }
    }
    
    // MARK: UI and User Interaction
    private func setupOutgoingBubble() -> JSQMessagesBubbleImage {
        let bubbleImageFactory = JSQMessagesBubbleImageFactory()
        return bubbleImageFactory!.outgoingMessagesBubbleImage(with: UIColor.jsq_messageBubbleBlue())
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
    
    private func addPhotoMessage(withId id: String, key: String, mediaItem: JSQPhotoMediaItem) {
        if let message = JSQMessage(senderId: id, displayName: "", media: mediaItem) {
            messages.append(message)
            
            if (mediaItem.image == nil) {
                photoMessageMap[key] = mediaItem
            }
            
            collectionView.reloadData()
        }
    }
    
    func sendPhotoMessage() -> String? {
        let itemRef = messageRef.childByAutoId()
        
        let messageItem = [
            "photoURL": imageURLNotSetKey,
            "senderId": senderId!,
            ]
        
        itemRef.setValue(messageItem)
        JSQSystemSoundPlayer.jsq_playMessageSentSound()
        finishSendingMessage()
        
        return itemRef.key
    }
    
    func setImageURL(_ url: String, forPhotoMessageWithKey key: String) {
        let itemRef = messageRef.child(key)
        itemRef.updateChildValues(["data": url])
    }
    
    override func didPressAccessoryButton(_ sender: UIButton) {
        let picker = UIImagePickerController()
        picker.delegate = self
        if UIImagePickerController.isSourceTypeAvailable(UIImagePickerControllerSourceType.camera) { // real device
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
            
        } else { // simulator
            picker.sourceType = .photoLibrary
            present(picker, animated: true, completion:nil)
        }
    }
    
}

// MARK: Image Picker Delegate
extension ChatViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [String : Any]) {
        picker.dismiss(animated: true, completion:nil)
        
        guard let photoReferenceUrl = info[UIImagePickerControllerReferenceURL] as? URL else {
            // Handle picking a Photo from the Camera
            guard let image = info[UIImagePickerControllerOriginalImage] as? UIImage else { return }
            if let key = sendPhotoMessage() {
                guard let imageData = UIImageJPEGRepresentation(image, 1.0) else { return }
                guard let uid = FIRAuth.auth()?.currentUser?.uid else { return }
                
                let imagePath = uid + "/\(Int(Date.timeIntervalSinceReferenceDate * 1000)).jpg"
                let metadata = FIRStorageMetadata()
                metadata.contentType = "image/jpeg"
                
                storageRef.child(imagePath).put(imageData, metadata: metadata) { (metadata, error) in
                    if let error = error {
                        print("Error uploading photo: \(error.localizedDescription)")
                        return
                    }
                    guard let metadataPath = metadata?.path else { return }
                    
                    self.setImageURL(self.storageRef.child(metadataPath).description, forPhotoMessageWithKey: key)
                }
            }
            
            return
        }
        
        // Handle picking a Photo from the Photo Library
        let assets = PHAsset.fetchAssets(withALAssetURLs: [photoReferenceUrl], options: nil)
        guard let asset = assets.firstObject else { return }
        guard let key = sendPhotoMessage() else { return }
        
        /*
        let manager = PHImageManager.default()
        manager.requestImage(for: asset, targetSize: CGSize(width: 640.0, height: 960.0), contentMode: .aspectFit, options: nil, resultHandler: { (result, info) -> Void in
            
            guard let result = result else { return }
            guard let uid = FIRAuth.auth()?.currentUser?.uid else { return }
            
            let path = "\(uid)/\(Int(Date.timeIntervalSinceReferenceDate * 1000)).jpg"
            guard let data = UIImageJPEGRepresentation(result, 1.0) else { return }
            
            let metadata = FIRStorageMetadata()
            metadata.contentType = "image/jpeg"
            
            self.storageRef.child(path).put(data, metadata: metadata, completion: { (metadata, error) in
                if let error = error {
                    print("Error uploading photo: \(error.localizedDescription)")
                    return
                }
                guard let metadataPath = metadata?.path else { return }
                
                self.setImageURL(self.storageRef.child(metadataPath).description, forPhotoMessageWithKey: key)
            })
        })
         */
        
        asset.requestContentEditingInput(with: nil, completionHandler: { (contentEditingInput, info) in
            guard let imageFileURL = contentEditingInput?.fullSizeImageURL else { return }
            guard let uid = FIRAuth.auth()?.currentUser?.uid else { return }
            
            let path = "\(uid)/\(Int(Date.timeIntervalSinceReferenceDate * 1000))/\(photoReferenceUrl.lastPathComponent)"
            
            self.storageRef.child(path).putFile(imageFileURL, metadata: nil) { (metadata, error) in
                if let error = error {
                    print("Error uploading photo: \(error.localizedDescription)")
                    return
                }
                guard let metadataPath = metadata?.path else { return }
                
                self.setImageURL(self.storageRef.child(metadataPath).description, forPhotoMessageWithKey: key)
            }
        })
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion:nil)
    }
}
