//
//  AppDelegate.swift
//  RouteToARM64SimSampleProject
//
//  Created by Aleksey Khalaidzhi on 27.09.2022.
//

import UIKit
import ShareSDK

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let vc = UIStoryboard(name: "Main", bundle: nil)
            .instantiateViewController(withIdentifier: "MainAppViewController")
        window?.rootViewController = vc
        window?.makeKeyAndVisible()

        ShareSDK.registPlatforms { register in
            register?.setupVKontakte(withApplicationId: "", secretKey: "", authType: .SSO)
            print("Hello from SharedSDK example");
        }

        return true
    }
}

