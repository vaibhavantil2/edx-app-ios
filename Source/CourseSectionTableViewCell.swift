//
//  CourseSectionTableViewCell.swift
//  edX
//
//  Created by Ehmad Zubair Chughtai on 04/06/2015.
//  Copyright (c) 2015 edX. All rights reserved.
//

import UIKit

protocol CourseSectionTableViewCellDelegate : AnyObject {
    func sectionCellChoseDownload(cell : CourseSectionTableViewCell, videos : [OEXHelperVideoDownload], forBlock block : CourseBlock)
    func sectionCellChoseShowDownloads(cell : CourseSectionTableViewCell)
    func reloadSectionCell(cell: UITableViewCell)
}

class CourseSectionTableViewCell: SwipeableCell, CourseBlockContainerCell {
    
    static let identifier = "CourseSectionTableViewCellIdentifier"
    
    fileprivate let content = CourseOutlineItemView()
    fileprivate let videosStream = BackedStream<[OEXHelperVideoDownload]>()
    fileprivate let downloadView = DownloadsAccessoryView()
    weak var delegate : CourseSectionTableViewCellDelegate?
    fileprivate var spinnerTimer = Timer()
    var courseID: String?
    var courseOutlineMode: CourseOutlineMode = .full {
        didSet {
            content.courseOutlineMode = courseOutlineMode
        }
    }
    
    var videos : OEXStream<[OEXHelperVideoDownload]> = OEXStream() {
        didSet {
            videosStream.backWithStream(videos)
        }
    }
    
    var courseQuerier: CourseOutlineQuerier?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.addSubview(content)
        
        content.snp.makeConstraints { make in
            if OEXConfig.shared().isNewDashboardEnabled && courseOutlineMode == .full {
                make.top.equalTo(contentView)
                make.bottom.equalTo(contentView)
                make.leading.equalTo(contentView).offset(StandardHorizontalMargin)
                make.trailing.equalTo(contentView).inset(StandardHorizontalMargin)
            } else {
                make.edges.equalTo(contentView)
            }
        }
        
        for notification in [NSNotification.Name.OEXDownloadProgressChanged, NSNotification.Name.OEXDownloadEnded, NSNotification.Name.OEXVideoStateChanged] {
            NotificationCenter.default.oex_addObserver(observer: self, name: notification.rawValue) { (_, observer, _) -> Void in
                if let state = observer.downloadStateForDownloads(videos: observer.videosStream.value) {
                    if observer.downloadView.state != state {
                        observer.downloadView.state = state
                    }
                } else {
                    observer.content.hideTrailingView()
                }
            }
        }
        
        let tapGesture = UITapGestureRecognizer()
        tapGesture.addAction {[weak self]_ in
            if let owner = self, owner.downloadView.state == .Downloading {
                owner.delegate?.sectionCellChoseShowDownloads(cell: owner)
            }
        }
        downloadView.addGestureRecognizer(tapGesture)
        setAccessibilityIdentifiers()
        
        if OEXConfig.shared().isNewDashboardEnabled {
            content.backgroundColor = OEXStyles.shared().neutralWhiteT()
        }
    }
    
    private func setAccessibilityIdentifiers() {
        accessibilityIdentifier = "CourseSectionTableViewCell:view"
        content.accessibilityIdentifier = "CourseSectionTableViewCell:content-view"
        downloadView.accessibilityIdentifier = "CourseSectionTableViewCell:download-view"
    }
    
    func hideLeadingView() {
        content.hideLeadingView()
    }
    
    private func setupDownloadView() {
        downloadView.downloadAction = { [weak self] in
            if let owner = self, let block = owner.block,
               let videos = owner.videosStream.value {
                owner.delegate?.sectionCellChoseDownload(cell: owner, videos: videos, forBlock: block)
            }
        }
        videosStream.listen(self) { [weak self] downloads in
            if let downloads = downloads.value,
               let downloadView = self?.downloadView,
               let state = self?.downloadStateForDownloads(videos: downloads) {
                self?.downloadView.state = state
                self?.content.trailingView = downloadView
                self?.downloadView.itemCount = downloads.count
            } else {
                self?.content.hideTrailingView()
            }
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        videosStream.backWithStream(OEXStream(value:[]))
        reset()
    }
    
    func downloadStateForDownloads(videos : [OEXHelperVideoDownload]?) -> DownloadsAccessoryView.State? {
        guard let videos = videos, videos.count > 0 else { return nil }
        
        let allCompleted = videos.reduce(true) {(acc, video) in
            return acc && video.downloadState == .complete
        }
        
        if allCompleted {
            return .Done
        }
        
        let filteredVideos = filterVideos(videos: videos)
        
        let allDownloading = filteredVideos.reduce(true) {(acc, video) in
            return acc && video.downloadState == .partial
        }
        
        if allDownloading {
            return .Downloading
        }
        else {
            return .Available
        }
    }
    
    private func filterVideos(videos: [OEXHelperVideoDownload])-> [OEXHelperVideoDownload]{
        var incompleteVideos:[OEXHelperVideoDownload]  = []
        for video in videos {
            // only return incomplete videos
            if video.downloadState != .complete {
                incompleteVideos.append(video)
            }
        }
        
        return incompleteVideos
    }
    
    
    public func deleteVideos(videos : [OEXHelperVideoDownload]) {
        OEXInterface.shared().deleteDownloadedVideos(videos) { _ in }
        OEXAnalytics.shared().trackSubsectionDeleteVideos(courseID: courseID ?? "", subsectionID: block?.blockID ?? "")
    }
    
    public func areAllVideosDownloaded(videos: [OEXHelperVideoDownload]) -> Bool {
        
        let videosState = downloadStateForDownloads(videos: videos)
        return (videosState == .Done)
    }
    
    var completionAction : (() -> ())?
    
    var block: CourseBlock? = nil {
        didSet {
            guard let block = block else { return }
            content.setTitleText(title: block.displayName, elipsis: false)
            content.isGraded = block.graded
            content.setDetailText(title: block.format ?? "", dueDate: block.dueDate, blockType: block.type)
            handleVideoBlockIfNeeded(block)
            setupDownloadView()
        }
    }
    
    private func handleVideoBlockIfNeeded(_ block: CourseBlock) {
        guard courseOutlineMode == .video,
              let sectionChild = courseQuerier?.childrenOfBlockWithID(blockID: block.blockID, forMode: .video).value,
              sectionChild.block.type == .Section,
              let unitChild = courseQuerier?.childrenOfBlockWithID(blockID: sectionChild.block.blockID, forMode: .video).value,
              unitChild.children.allSatisfy ({ $0.isCompleted })
        else {
            handleBlockNormally(block)
            return
        }
        
        completionAction?()
        showCompletionBackground()
    }
    
    private func handleBlockNormally(_ block: CourseBlock) {
        if block.isCompleted {
            let shouldShowIcon = courseOutlineMode == .full ? true : false
            showCompletionBackground(showIcon: shouldShowIcon)
        } else {
            showNeutralBackground()
        }
    }
    
    private func showCompletionBackground(showIcon: Bool = true) {
        content.backgroundColor = OEXStyles.shared().successXXLight()
        content.setContentIcon(icon: showIcon ? Icon.CheckCircle : nil, color: OEXStyles.shared().successBase())
        content.setSeperatorColor(color: OEXStyles.shared().successXLight())
        content.setCompletionAccessibility(completion: true)
    }
    
    private func showNeutralBackground() {
        content.backgroundColor = OEXStyles.shared().neutralWhite()
        content.setContentIcon(icon: nil, color: .clear)
        content.setSeperatorColor(color: OEXStyles.shared().neutralXLight())
        content.setCompletionAccessibility()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension CourseSectionTableViewCell: SwipeableCellDelegate {
    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath, for orientation: SwipeActionsOrientation) -> [SwipeActionButton]? {
        
        var downloadVideos:[OEXHelperVideoDownload] = []
        videosStream.listen(self) { downloads in
            if let videos = downloads.value {
                downloadVideos = videos
            }
        }
        
        if(!areAllVideosDownloaded(videos: downloadVideos)) {
            return nil
        }
        let deleteButton = SwipeActionButton(title: nil, image: Icon.DeleteIcon.imageWithFontSize(size: 20)) {[weak self] action, indexPath in
            if let owner = self {
                //Showing a spinner while deleting video
                owner.deleteVideos(videos: downloadVideos)
                owner.downloadView.state = .Deleting
                owner.spinnerTimer = Timer.scheduledTimer(timeInterval: 0.4, target:owner, selector: #selector(owner.invalidateTimer), userInfo: nil, repeats: true)
            }
        }
        return [deleteButton]
    }
    
    @objc private func invalidateTimer(){
        spinnerTimer.invalidate()
        downloadView.state = .Done
        delegate?.reloadSectionCell(cell: self)
    }
}

extension CourseSectionTableViewCell {
    public func t_setup() -> OEXStream<[OEXHelperVideoDownload]> {
        return videos
    }
    
    public func t_areAllVideosDownloaded(videos: [OEXHelperVideoDownload]) -> Bool {
        return areAllVideosDownloaded(videos: videos)
    }
}
