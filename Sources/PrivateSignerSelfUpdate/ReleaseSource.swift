import PrivateSignerKit

/// A self-update candidate is now the immutable ProjectVersion returned by the Worker.
///
/// The client no longer discovers GitHub releases or receives the unsigned IPA URL.
public typealias SelfUpdateCandidate = ProjectVersion
