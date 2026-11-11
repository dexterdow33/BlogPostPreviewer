import Foundation

/// How to reach the newsroom, as granitestatereport.com/tips/ lists it (Send a Tip v1.5,
/// October 11, 2026). Change these only when the site changes.
public enum GSRContact {
    public static let site = URL(string: "https://granitestatereport.com/")!
    public static let email = "granitestatereport@gmail.com"
    public static let phoneDisplay = "(603) 931-9264"
    public static let phoneURL = URL(string: "tel:+16039319264")!
    public static let signalUsername = "GraniteStateReport.09"
    /// The username link the Send a Tip page puts on the username, copied from the page.
    /// Signal makes these links itself; the app never builds one.
    public static let signalLink = URL(string: "https://signal.me/#eu/2UqjPNE4nfo0Rj4vYOtuDvBTVw-0uZp8gdU-9Dr_ycK8bJ29bAJIJr8jlsxYUBXq")!
    public static let mailingAddress = ["Granite State Report", "43 Sargent Street", "Northfield, NH 03276"]

    public static let tipsPage = URL(string: "https://granitestatereport.com/tips/")!
    public static let privacyPolicy = URL(string: "https://granitestatereport.com/privacy-policy/")!
    public static let termsOfUse = URL(string: "https://granitestatereport.com/terms-of-use/")!
    public static let codeOfEthics = URL(string: "https://granitestatereport.com/code-of-ethics/")!
    public static let billTracker = URL(string: "https://granitestatereport.com/nh-bill-tracker/")!

    public static var emailURL: URL { URL(string: "mailto:\(email)")! }
}
