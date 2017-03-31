//
//  SessionManager.swift
//  Kryptonite
//
//  Created by Alex Grinman on 9/8/16.
//  Copyright © 2016 KryptCo, Inc. All rights reserved.
//

import Foundation
import JSON


//MARK: Defaults

extension UserDefaults {
    static var sessionDefaults:UserDefaults? {
        return UserDefaults(suiteName: "kr_session_defaults")
    }
}


class SessionManager {
    
    private static let ListKey = "kr_session_list"
    
    
    private var mutex = Mutex()
    private var sessions:[String:Session]
    
    
    private static var sharedSessionManagerMutex = Mutex()
    private static var sharedSessionManager:SessionManager?

    class var shared:SessionManager {
        defer { sharedSessionManagerMutex.unlock() }
        sharedSessionManagerMutex.lock()
        
        guard let sm = sharedSessionManager else {
            sharedSessionManager = SessionManager(SessionManager.load())
            return sharedSessionManager!
        }
        return sm
    }
    
    init(_ sessions:[String:Session] = [:]) {
        self.sessions = sessions
    }

    
    var all:[Session] {
        defer { mutex.unlock() }
        mutex.lock()
        
        return [Session](sessions.values)
    }
    
    func get(queue:QueueName) -> Session? {
        return all.filter({$0.pairing.queue == queue}).first
    }
    
    func get(id:String) -> Session? {
        defer { mutex.unlock() }
        mutex.lock()

        return sessions[id]
    }
    
    func get(deviceName:String) -> Session? {
        return all.filter({ $0.pairing.name == deviceName }).first
    }
    
    
    func add(session:Session) {
        defer { mutex.unlock() }
        mutex.lock()

        let didSavePub = KeychainStorage().set(key: Session.KeychainKey.pub.tag(for: session.id), value: session.pairing.keyPair.publicKey.toBase64())
        let didSavePriv = KeychainStorage().set(key: Session.KeychainKey.priv.tag(for: session.id), value: session.pairing.keyPair.secretKey.toBase64())

        if !(didSavePub && didSavePriv) { log("could not save keypair for id: \(session.id)", .error) }
        sessions[session.id] = session
        save()
    }
    
    func remove(session:Session) {
        defer { mutex.unlock() }
        mutex.lock()

        sessions.removeValue(forKey: session.id)
        save()
    }
    
    func destroy() {
        defer { mutex.unlock() }
        mutex.lock()

        UserDefaults.group?.removeObject(forKey: SessionManager.ListKey)
        SessionManager.sharedSessionManager = nil
        sessions = [:]
    }
    
    
    func save() {
        defer { mutex.unlock() }
        mutex.lock()

        let data = sessions.values.map({ $0.object }) as [Any]
        UserDefaults.group?.set(data, forKey: SessionManager.ListKey)
        UserDefaults.group?.synchronize()
    }
    
    
    private class func load() -> [String:Session] {
        guard let jsonList = UserDefaults.group?.array(forKey: SessionManager.ListKey) as? [Object]
        else {
            return [:]
        }
        
        var map:[String:Session] = [:]
        do {
            try [Session](json: jsonList).forEach({ map[$0.id] = $0 })
        } catch {
            log("could not parse sessions from persistant storage: \(error)", .error)
        }

        
        return map
    }

    
    //MARK: Handling old version sessions 
    
    static func oldVersionSessionNames() -> [String] {
        guard let jsonList = UserDefaults.standard.array(forKey: SessionManager.ListKey) as? [Object]
        else {
            return []
        }
        
        var oldSessionNames = [String]()
        
        jsonList.forEach {
            guard   let sessionName = $0["name"] as? String,
                    $0["version"] == nil
            else {
                return
            }
            
            oldSessionNames.append(sessionName)
        }
        
        return oldSessionNames
    }
    
    static func hasOldSessions() -> (Bool, [String]) {
        let oldSessionNames = SessionManager.oldVersionSessionNames()
        return (!oldSessionNames.isEmpty, oldSessionNames)
    }
    
    static func clearOldSessions() {
        UserDefaults.standard.removeObject(forKey: SessionManager.ListKey)
    }
}
