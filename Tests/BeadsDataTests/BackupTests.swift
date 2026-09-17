import BeadsCore
import BeadsData
import Foundation
import Testing

@Suite("Reading bd's backup status")
struct BackupStatusTests {
    @Test("a configured backup reports where it goes and when it last went")
    func configured() throws {
        let json = """
        {
          "backup": {"last_dolt_commit": "", "timestamp": "0001-01-01T00:00:00Z"},
          "database_size": {"bytes": 1468006, "human": "1.4 MB"},
          "dolt": {
            "backup_name": "default",
            "backup_url": "file:///Users/someone/Backups/beady.dolt",
            "configured": true,
            "created_at": "2026-09-17T01:11:23Z",
            "last_sync": "2026-09-17T01:11:31Z",
            "sync_duration": "70.878958ms"
          }
        }
        """
        let status = try BDJSON.decodeBackupStatus(Data(json.utf8))
        #expect(status.isConfigured)
        #expect(status.destination == "/Users/someone/Backups/beady.dolt", "shown as a path, not a URL")
        #expect(status.databaseSize == "1.4 MB")
        #expect(status.lastSync != nil)
    }

    @Test("no backup configured is a state, not a failure")
    func notConfigured() throws {
        let json = """
        {"backup": {}, "database_size": {"bytes": 0, "human": "0 B"}, "dolt": {"configured": false}}
        """
        let status = try BDJSON.decodeBackupStatus(Data(json.utf8))
        #expect(!status.isConfigured)
        #expect(status.destination == nil)
        #expect(status.lastSync == nil)
    }

    @Test("the commands are the ones bd documents, and only sync and init write")
    func commands() {
        #expect(BDCommand.backupStatus.arguments == ["backup", "status", "--json"])
        #expect(BDCommand.backupStatus.isReadOnly)
        #expect(BDCommand.backupSync.arguments == ["backup", "sync"])
        #expect(!BDCommand.backupSync.isReadOnly)
        #expect(BDCommand.backupInit("/tmp/dest").arguments == ["backup", "init", "/tmp/dest"])
        #expect(!BDCommand.backupInit("/tmp/dest").isReadOnly)
    }
}
