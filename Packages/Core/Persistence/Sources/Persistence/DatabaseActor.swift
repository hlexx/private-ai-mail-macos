import Foundation

@globalActor
public actor DatabaseActor: GlobalActor {
    public static let shared = DatabaseActor()
}
