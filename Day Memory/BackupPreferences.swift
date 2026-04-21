//
//  BackupPreferences.swift
//  Day Memory
//

import Foundation

enum BackupPreferences {
    static let autoICloudBackupKey = "daymemory.backup.autoICloud"
    static let lastICloudBackupKey = "daymemory.backup.lastAt"

    static var isAutoICloudBackupEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: autoICloudBackupKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoICloudBackupKey) }
    }

    static var lastICloudBackupDate: Date? {
        get { UserDefaults.standard.object(forKey: lastICloudBackupKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastICloudBackupKey) }
    }
}
