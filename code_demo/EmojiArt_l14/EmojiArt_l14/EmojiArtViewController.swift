//
//  EmojiArtViewController.swift
//  EmojiArt
//
//  Created by Xue Yu on 1/1/18.
//  Copyright © 2018 XueYu. All rights reserved.
//

import UIKit

// takes a UILabel, return EmojiInfo
extension EmojiArt.EmojiInfo
{
    init?(label: UILabel) {
        if let attributedText = label.attributedText, let font = attributedText.font {
            x = Int(label.center.x)
            y = Int(label.center.y)
            text = attributedText.string
            size = Int(font.pointSize)
        } else {
            return nil
        }
    }
    
}

class EmojiArtViewController: UIViewController, UIDropInteractionDelegate, UIScrollViewDelegate, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UICollectionViewDragDelegate, UICollectionViewDropDelegate
{
    
    // MARK: - Model
    
    var emojiArt: EmojiArt? {
        get {
            if let url = emojiArtBackgroundImage.url {
                
                // flatMap ignores nil
                let emojis = emojiArtView.subviews.flatMap { $0 as? UILabel }.flatMap { EmojiArt.EmojiInfo.init(label: $0) }
                return EmojiArt(url: url, emojis: emojis)
            }
            
            return nil
        }
        set {
            // clear things first
            emojiArtBackgroundImage = (nil, nil)
            emojiArtView.subviews.flatMap{ $0 as? UILabel }.forEach{ $0.removeFromSuperview() }
            
            if let url = newValue?.url {
                imageFetcher = ImageFetcher(fetch: url) { (url, image) in
                    DispatchQueue.main.async {
                        // set background image
                        self.emojiArtBackgroundImage = (url, image)
                        // add labels
                        newValue?.emojis.forEach {
                            // Utility function
                            let attributedText = $0.text.attributedString(withTextStyle: .body, ofSize: CGFloat($0.size))
                            self.emojiArtView.addLabel(with: attributedText, centeredAt: CGPoint(x: $0.x, y: $0.y))
                        }
                    }
                }
            }
        }
    }

    // this will set from the file choser
    var document: EmojiArtDocument?
    
    // Actually we should save when it changed
    // let view talk back to the controller - use delegate, not done here
    // as in Pages I don't press save, as it is auto saved
    @IBAction func save(_ sender: UIBarButtonItem? = nil) {
        document?.emojiArt = emojiArt
        if document?.emojiArt != nil {
            document?.updateChangeCount(.done)
        }
    }
    
    // load if it exists
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        //
        document?.open { success in
            if success {
                self.title = self.document?.localizedName
                self.emojiArt = self.document?.emojiArt
            }
        }
    }
    
    
    // easy one - just close the document
    @IBAction func close(_ sender: UIBarButtonItem) {
        // won't have save if we have auto track changes
        save()
        if document?.emojiArt != nil {
            document?.thumbnail = emojiArtView.snapshot
        }
        // dimiss itself
        dismiss(animated: true){
            self.document?.close()
        }
    }
    
    

    
    @IBOutlet weak var dropZone: UIView! {
        didSet {
            dropZone.addInteraction(UIDropInteraction(delegate: self))
        }
    }
    
    var emojiArtView = EmojiArtView()
    
    @IBOutlet weak var scrollViewWidth: NSLayoutConstraint!
    @IBOutlet weak var scrollViewHeight: NSLayoutConstraint!
    
    // MARK: - scrollview
    // embed the emojiArtView in scrollView, it's like what we did in Cassini
    @IBOutlet weak var scrollView: UIScrollView! {
        didSet {
            scrollView.delegate = self
            scrollView.minimumZoomScale = 0.1
            scrollView.maximumZoomScale = 5.0
            scrollView.addSubview(emojiArtView)
        }
    }
    
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        scrollViewHeight.constant = scrollView.contentSize.height
        scrollViewWidth.constant = scrollView.contentSize.width
    }
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return emojiArtView
    }
    
    // background storage
    private var _emojiArtBackgroundImageURL: URL?
    

    var emojiArtBackgroundImage: (url: URL?, image: UIImage?) {
        get {
            return (_emojiArtBackgroundImageURL, emojiArtView.backgroundImage)
        }
        set {
            _emojiArtBackgroundImageURL = newValue.url
            scrollView?.zoomScale = 1.0
            emojiArtView.backgroundImage = newValue.image
            let size = newValue.image?.size ?? CGSize.zero
            emojiArtView.frame = CGRect(origin: CGPoint.zero, size: size)
            scrollView?.contentSize = size
            scrollViewHeight?.constant = size.height
            scrollViewWidth?.constant = size.width
            if let dropZone = self.dropZone, size.width > 0, size.height > 0 {
                scrollView.zoomScale = max(dropZone.bounds.size.width / size.width, dropZone.bounds.size.height / size.height)
            }
        }
    }
    
    
    
    // MARK: - drop for dropZone
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        return session.canLoadObjects(ofClass: NSURL.self) && session.canLoadObjects(ofClass: UIImage.self)
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        return UIDropProposal(operation: .copy)
    }
    
    
    
    var imageFetcher: ImageFetcher!

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        imageFetcher = ImageFetcher(){ (url, image) in
            DispatchQueue.main.async {
                self.emojiArtBackgroundImage = (url, image)
            }
        }
        
        
        session.loadObjects(ofClass: NSURL.self) { nsurls in
            if let url = nsurls.first as? URL{
                self.imageFetcher.fetch(url)
            }
        }
        
        session.loadObjects(ofClass: UIImage.self) { images in
            if let image = images.first as? UIImage{
                self.imageFetcher.backup = image
            }
        }
    }
    
    // MARK: Emoji CollectionView
    
    @IBOutlet weak var emojiCollectionView: UICollectionView! {
        didSet {
            emojiCollectionView.dataSource = self
            emojiCollectionView.delegate = self
            emojiCollectionView.dragDelegate = self
            emojiCollectionView.dropDelegate = self
            
            // true default iPad, false default on iPhone
            emojiCollectionView.dragInteractionEnabled = true
        }
    }
    
    var emojis = "😀🎁✈️🎱🍎🐶🐝☕️🎼🚲♣️👨‍🎓✏️🌈🤡🎓👻☎️".map { String($0) }
    

    

    
    // use this to make font scale as we adjust in System Settings
    // but this will not work well now because we set the collection view height fixed
    private var font: UIFont {
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont.preferredFont(forTextStyle: .body).withSize(64.0))
    }
    

    
    // MARK: Emoji CollectionView drag
    
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        // let drop know this is a local drag
        session.localContext = collectionView
        return dragItems(at: indexPath)
    }

    // this is add more when drag more
    func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
        return dragItems(at: indexPath)
    }
    
    // provide what to drag
    private func dragItems(at indexPath: IndexPath) -> [UIDragItem] {
        // disable dragging when adding emoji
        if !addingEmoji, let attributedString = (emojiCollectionView.cellForItem(at: indexPath) as? EmojiCollectionViewCell)?.label.attributedText {
            let dragItem =  UIDragItem(itemProvider: NSItemProvider(object: attributedString))
            // drag local, we can use this
            dragItem.localObject = attributedString
            return [dragItem]
        } else {
            return []
        }
    }
    
    
    // MARK: Emoji CollectionView drop
    
    func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
        return session.canLoadObjects(ofClass: NSAttributedString.self)
    }
    
    // after this method implements, it already had the action of drop
    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        if let indexPath = destinationIndexPath, indexPath.section == 1 {
            // collectionview drop different from the normal drop is that we can do this intent, choose to drop insert or add it
            // get the localContext from the drag, so we know whether this drop's drag from the collection view and thus we know whether it should be copy or move
            let isSelf = (session.localDragSession?.localContext as? UICollectionView) == collectionView
            return UICollectionViewDropProposal(operation: isSelf ? .move : .copy, intent: .insertAtDestinationIndexPath)
        } else {
            // do not also drop emoji to plus button
            return UICollectionViewDropProposal(operation: .cancel)
        }

    }
    
    
    func collectionView(_ collectionView: UICollectionView,
                        performDropWith coordinator: UICollectionViewDropCoordinator) {
        // coordinator knows everything
        let destinationIndexPath = coordinator.destinationIndexPath ?? IndexPath(item: 0, section: 0)
        // uicollectionview drop items
        for item in coordinator.items {
            // know this is from the collection view
            if let sourceIndexPath = item.sourceIndexPath {
                // drag locally, so we can use this
                if let attributedString = item.dragItem.localObject as? NSAttributedString {
                    
                    // do not reload data for effeciency
                    // we use perform batch because if we do it directly
                    // it may goes wrong because model might not in sync with the model
                    collectionView.performBatchUpdates({
                        emojis.remove(at: sourceIndexPath.item)
                        emojis.insert(attributedString.string, at: destinationIndexPath.item)
                        
                        collectionView.deleteItems(at: [sourceIndexPath])
                        collectionView.insertItems(at: [destinationIndexPath])
                    })
                    // do the drop, animate the drop happening
                    coordinator.drop(item.dragItem, toItemAt: destinationIndexPath)
                }
            }
                // we don't have a indexPath, it comes from outside
            else {
                // drop the item to a placeholder because it is async
                // reuseIdentifier is like EmojiCell
                let placeHolderContext = coordinator.drop(
                    item.dragItem,
                    to:  UICollectionViewDropPlaceholder(insertionIndexPath: destinationIndexPath, reuseIdentifier: "DropPlaceholderCell"))
                
                // this closure is not on main queue
                item.dragItem.itemProvider.loadObject(ofClass: NSAttributedString.self) { (provider, error) in
                    DispatchQueue.main.async {
                        // get the string, update the model
                        if let attributedString = provider as? NSAttributedString {
                            placeHolderContext.commitInsertion(dataSourceUpdates: { insertionIndexPath in
                                self.emojis.insert(attributedString.string, at: insertionIndexPath.item)
                            })
                         // not get the string, delete
                        } else {
                            placeHolderContext.deletePlaceholder()
                        }
                    }
                }
                
            }
        }
        
    }
    
    
    
    // MARK: - Add emoji
    
    private var addingEmoji = false
    
    @IBAction func addEmoji() {
        addingEmoji = true
        emojiCollectionView.reloadSections(IndexSet(integer: 0))
    }
    
    // 2 sections, section 0 to add emoji
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 2
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        
        switch section {
        case 0: return 1
        case 1: return emojis.count
        default: return 0
        }
    }
    
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.section == 1  {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "EmojiCell", for: indexPath)
            if let emojiCell = cell as? EmojiCollectionViewCell {
                let text = NSAttributedString(string: emojis[indexPath.item], attributes: [.font : font])
                emojiCell.label.attributedText = text
            }
            return cell
        } else if addingEmoji {
            // if we're adding emoji, we'll put the input cell there
            // and whenever this addingEmoji is true, we'll reload section 0
            
            // and we set the 'clears when begins editing' to true
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "EmojiInputCell", for: indexPath)
            // call the resignationhandler
            if let inputCell = cell as? TextFieldCollectionViewCell {
                inputCell.resignationHandler = { [weak self, unowned inputCell] in
                    if let text = inputCell.textField.text {
                        // self points to collectionview, collectionview's cell points to self
                        self?.emojis = (text.map{String($0)} + self!.emojis).uniquified
                    }
                    // stop adding emoji and reload data 
                    self?.addingEmoji = false
                    self?.emojiCollectionView.reloadData()
                }
            }
            
            return cell
        } else {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "AddEmojiButtonCell", for: indexPath)
            return cell
        }
    }
    
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if addingEmoji && indexPath.section == 0 {
            // when adding emoji, want the textfield be wide
            return CGSize(width: 300, height: 80)
        } else {
            return CGSize(width: 80, height: 80)
        }
        
    }
    
    
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        // when textfield comes up, make the textfield become first responder so we can have keyboard up
        if let inputCell = cell as? TextFieldCollectionViewCell {
            inputCell.textField.becomeFirstResponder()
        }
    }
    
    
    
    
    


    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}
