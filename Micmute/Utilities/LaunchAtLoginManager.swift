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
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Error updating launch at login: \(error)")
        }
    }
}
