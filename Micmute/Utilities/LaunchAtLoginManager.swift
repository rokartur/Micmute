//
//  LaunchAtLoginManager.swift
//  Micmute
//
//  Created by Artur Rok on 11/02/2025.
//

import Foundation
import ServiceManagement

struct LaunchAtLoginManager {
    static func update(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            print("Error updating launch at login: \(error)")
        }
    }
}
