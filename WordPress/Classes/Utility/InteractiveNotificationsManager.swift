import Foundation
import UserNotifications

/// In this class, we'll encapsulate all of the code related to UNNotificationCategory and
/// UNNotificationAction instantiation, along with the required handlers.
///
final public class InteractiveNotificationsManager : NSObject
{
    // MARK: - Public Properties


    /// Returns the shared InteractiveNotificationsManager instance.
    ///
    static let sharedInstance = InteractiveNotificationsManager()


    /// Returns the SharedApplication instance. This is meant for Unit Testing purposes.
    ///
    var sharedApplication : UIApplication {
        return UIApplication.sharedApplication()
    }



    // MARK: - Public Methods


    /// Registers the device for User Notifications.
    ///
    /// This method should be called once during the app initialization process.
    ///
    public func registerForUserNotifications() {
        if sharedApplication.isRunningSimulator() || build(.Alpha) {
            return
        }

        if #available(iOS 10.0, *) {
            let notificationCenter = UNUserNotificationCenter.currentNotificationCenter()
            notificationCenter.delegate = self
            notificationCenter.setNotificationCategories(supportedNotificationCategories())
        }
    }

    /// Requests authorization to interact with the user when notifications arrive.
    ///
    /// The first time this method is called it will ask the user for permission to show notifications.
    /// Because of this, this should be called only when we know we will need to show notifications (for instance, after login).
    ///
    public func requestAuthorization() {
        if sharedApplication.isRunningSimulator() || build(.Alpha) {
            return
        }

        if #available(iOS 10.0, *) {
            let notificationCenter = UNUserNotificationCenter.currentNotificationCenter()
            notificationCenter.requestAuthorizationWithOptions([.Badge, .Sound, .Alert], completionHandler: { _ in })
        } else {
            let settings = UIUserNotificationSettings(forTypes: [.Badge, .Sound, .Alert], categories: supportedNotificationCategories())
            sharedApplication.registerUserNotificationSettings(settings)
        }
    }

    /// Handle an action taken from a remote notification
    ///
    /// - Parameters:
    ///     - identifier: The identifier of the action
    ///     - remoteNotification: the notification object
    ///
    public func handleActionWithIdentifier(identifier: String, remoteNotification: NSDictionary, responseText: String?) {
        guard AccountHelper.isDotcomAvailable() else {
            return
        }

        guard let noteId = remoteNotification.objectForKey("note_id") as? NSNumber else {
            return
        }

        guard let siteID = remoteNotification.objectForKey("blog_id") as? NSNumber else {
            return
        }

        guard let commentID = remoteNotification.objectForKey("comment_id") as? NSNumber else {
            return
        }

        if #available(iOS 10.0, *) {
            if identifier == UNNotificationDefaultActionIdentifier {
                showDetailsWithNoteID(noteId)
                return
            }
        }

        guard let action = NoteActionDefinition(rawValue: identifier) else {
            return
        }

        switch action {
        case .CommentApprove:
            approveCommentWithCommentID(commentID, siteID: siteID)
        case .CommentLike:
            likeCommentWithCommentID(commentID, siteID: siteID)
        case .CommentReply:
            if let responseText = responseText {
                replyToCommentWithCommentID(commentID, siteID: siteID, content: responseText)
            } else {
                DDLogSwift.logError("Tried to reply to a comment notification with no text")
            }
        }
    }



    // MARK: - Private Helpers


    /// Likes a comment
    ///
    /// - Parameters:
    ///     - commentID: The comment identifier
    ///     - siteID: The site identifier
    ///
    private func likeCommentWithCommentID(commentID: NSNumber, siteID: NSNumber) {
        let context = ContextManager.sharedInstance().mainContext
        let service = CommentService(managedObjectContext: context)

        service.likeCommentWithID(commentID, siteID: siteID, success: {
            DDLogSwift.logInfo("Liked comment from push notification")
        }, failure: { error in
            DDLogSwift.logInfo("Couldn't like comment from push notification")
        })
    }


    /// Approves a comment
    ///
    /// - Parameters:
    ///     - commentID: The comment identifier
    ///     - siteID: The site identifier
    ///
    private func approveCommentWithCommentID(commentID: NSNumber, siteID: NSNumber) {
        let context = ContextManager.sharedInstance().mainContext
        let service = CommentService(managedObjectContext: context)

        service.approveCommentWithID(commentID, siteID: siteID, success: {
            DDLogSwift.logInfo("Successfully moderated comment from push notification")
        }, failure: { error in
            DDLogSwift.logInfo("Couldn't moderate comment from push notification")
        })
    }


    /// Opens the details for a given notificationId
    ///
    /// - Parameter noteID: The Notification's Identifier
    ///
    private func showDetailsWithNoteID(noteId: NSNumber) {
        WPTabBarController.sharedInstance().showNotificationsTabForNoteWithID(noteId.stringValue)
    }


    /// Replies to a comment
    ///
    /// - Parameters:
    ///     - commentID: The comment identifier
    ///     - siteID: The site identifier
    ///     - content: The text for the comment reply
    ///
    private func replyToCommentWithCommentID(commentID: NSNumber, siteID: NSNumber, content: String) {
        let context = ContextManager.sharedInstance().mainContext
        let service = CommentService(managedObjectContext: context)

        service.replyToCommentWithID(commentID, siteID: siteID, content: content, success: {
            DDLogSwift.logInfo("Successfully replied comment from push notification")
        }, failure: { error in
            DDLogSwift.logInfo("Couldn't reply to comment from push notification")
        })
    }




    // MARK: - Private: UNNotification Helpers


    /// Returns a collection of *UNNotificationCategory* instances, for each one of the
    /// supported NoteCategoryDefinition enum case's.
    ///
    /// - Returns: A set of *UNNotificationCategory* instances.
    ///
    @available(iOS 10.0, *)
    private func supportedNotificationCategories() -> Set<UNNotificationCategory> {
        let categories: [UNNotificationCategory] = NoteCategoryDefinition.allDefinitions.map({ $0.notificationCategory() })
        return Set(categories)
    }




    /// Returns a collection of *UIUserNotificationCategory* instances, for each one of the
    /// supported NoteCategoryDefinition enum case's.
    ///
    /// - Returns: A set of *UIUserNotificationCategory* instances.
    /// - Note: This method is only used for iOS 9 compatibility
    ///
    private func supportedNotificationCategories() -> Set<UIUserNotificationCategory> {
        let categories: [UIUserNotificationCategory] = NoteCategoryDefinition.allDefinitions.map({ $0.notificationCategory() })
        return Set(categories)
    }



    /// Describes information about Custom Actions that WPiOS can perform, as a response to
    /// a Push Notification event.
    ///
    private enum NoteCategoryDefinition : String {
        case CommentApprove         = "approve-comment"
        case CommentLike            = "like-comment"
        case CommentReply           = "replyto-comment"
        case CommentReplyWithLike   = "replyto-like-comment"

        var actions : [NoteActionDefinition] {
            switch self {
            case CommentApprove:
                return [.CommentApprove]
            case CommentLike:
                return [.CommentLike]
            case CommentReply:
                return [.CommentReply]
            case CommentReplyWithLike:
                return [.CommentReply, .CommentLike]
            }
        }

        var identifier : String {
            return rawValue
        }

        @available(iOS 10.0, *)
        func notificationCategory() -> UNNotificationCategory {
            return UNNotificationCategory(
                identifier: identifier,
                actions: actions.map({ $0.notificationAction() }),
                intentIdentifiers: [],
                options: [])
        }

        // iOS 9 compatibility
        func notificationCategory() -> UIUserNotificationCategory {
            let category = UIMutableUserNotificationCategory()
            category.identifier = identifier
            category.setActions(actions.map({ $0.notificationAction() }), forContext: .Default)
            return category
        }

        static var allDefinitions = [CommentApprove, CommentLike, CommentReply, CommentReplyWithLike]
    }



    /// Describes the custom actions that WPiOS can perform in response to a Push notification.
    ///
    private enum NoteActionDefinition : String {
        case CommentApprove = "COMMENT_MODERATE_APPROVE"
        case CommentLike    = "COMMENT_LIKE"
        case CommentReply   = "COMMENT_REPLY"

        var description : String {
            switch self {
            case CommentApprove:
                return NSLocalizedString("Approve", comment: "Approve comment (verb)")
            case CommentLike:
                return NSLocalizedString("Like", comment: "Like (verb)")
            case CommentReply:
                return NSLocalizedString("Reply", comment: "Reply to a comment (verb)")
            }
        }

        var destructive : Bool {
            return false
        }

        var identifier : String {
            return rawValue
        }

        var requiresAuthentication : Bool {
            return false
        }

        var requiresForeground : Bool {
            return false
        }

        @available(iOS 10.0, *)
        var notificationActionOptions: UNNotificationActionOptions {
            var options = UNNotificationActionOptions()
            if requiresAuthentication {
                options.insert(.AuthenticationRequired)
            }
            if destructive {
                options.insert(.Destructive)
            }
            if requiresForeground {
                options.insert(.Foreground)
            }
            return options
        }

        @available(iOS 10.0, *)
        func notificationAction() -> UNNotificationAction {
            switch self {
            case .CommentReply:
                return UNTextInputNotificationAction(identifier: identifier,
                                                     title: description,
                                                     options: notificationActionOptions,
                                                     textInputButtonTitle: NSLocalizedString("Reply", comment: ""),
                                                     textInputPlaceholder: NSLocalizedString("Write a reply…", comment: "Placeholder text for inline compose view"))
            default:
                return UNNotificationAction(identifier: identifier, title: description, options: notificationActionOptions)
            }
        }

        // iOS 9 compatibility
        func notificationAction() -> UIUserNotificationAction {
            let action = UIMutableUserNotificationAction()
            action.identifier = identifier
            action.title = description
            action.activationMode = requiresForeground ? .Foreground : .Background
            action.destructive = destructive
            action.authenticationRequired = requiresAuthentication
            if self == CommentReply {
                action.behavior = .TextInput
            }
            return action
        }

        static var allDefinitions = [CommentApprove, CommentLike, CommentReply]
    }
}

@available(iOS 10.0, *)
extension InteractiveNotificationsManager: UNUserNotificationCenterDelegate {
    public func userNotificationCenter(center: UNUserNotificationCenter, didReceiveNotificationResponse response: UNNotificationResponse, withCompletionHandler completionHandler: () -> Void) {
        let responseText = (response as? UNTextInputNotificationResponse)?.userText
        handleActionWithIdentifier(response.actionIdentifier, remoteNotification: response.notification.request.content.userInfo, responseText: responseText)
        completionHandler()
    }
}
