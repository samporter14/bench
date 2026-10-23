// FindFixtures.swift — a made-up copy of the part of Claude Science's database
// that Find reads, for the tests: the four tables with every column they have
// in the 0.1.70 migrations, and their indexes, copied from the schema that
// `drizzle/sqlite/*.sql` makes (reading those migrations is how the schema was
// learned; the real database is never opened). Rows are made up here.
import Foundation
import Testing
@testable import Bench

enum FindSchema {
    /// `CREATE TABLE` for frames, projects, artifacts and artifact_versions.
    static let tables: [String] = [
#"""
CREATE TABLE `artifact_versions` (
	`id` text(36) PRIMARY KEY NOT NULL,
	`artifact_id` text(36) NOT NULL,
	`version_number` integer NOT NULL,
	`frame_id` text(36),
	`content_type` text(100) NOT NULL,
	`size_bytes` integer NOT NULL,
	`checksum` text(64) NOT NULL,
	`storage_path` text(512) NOT NULL,
	`created_at` integer NOT NULL,
	`extracted_code` text,
	`code_description` text,
	`lineage_messages` text,
	`agent_name` text(255),
	`language` text(50),
	`is_intermediate` integer NOT NULL,
	`dependency_mappings` text,
	`environment_snapshot` text,
	`annotations` text,
	`parent_version_id` text(36), `lineage_snapshot_hash` text(64), `env_snapshot_hash` text(64), `producing_cell_id` text(36), `cell_sources` text, `is_checkpoint` integer DEFAULT 0,
	FOREIGN KEY (`artifact_id`) REFERENCES `artifacts`(`id`) ON UPDATE no action ON DELETE cascade
)
"""#,
#"""
CREATE TABLE `artifacts` (
	`id` text(36) PRIMARY KEY NOT NULL,
	`project_id` text(255) NOT NULL,
	`root_frame_id` text(36) NOT NULL,
	`frame_id` text(36),
	`filename` text(255) NOT NULL,
	`created_at` integer NOT NULL,
	`latest_version_id` text(36),
	`is_user_upload` integer NOT NULL,
	`is_ephemeral` integer NOT NULL,
	`folder_id` text(36),
	`sort_order` integer NOT NULL,
	`priority` text(20) DEFAULT 'unknown' NOT NULL, superseded_by_artifact_id text, `consumed_at` integer, `is_branch_mint` integer DEFAULT false NOT NULL, `agent_rename_history` text, `retention` text,
	FOREIGN KEY (`project_id`) REFERENCES `projects`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`latest_version_id`) REFERENCES `artifact_versions`(`id`) ON UPDATE no action ON DELETE set null,
	FOREIGN KEY (`folder_id`) REFERENCES `artifact_folders`(`id`) ON UPDATE no action ON DELETE set null
)
"""#,
#"""
CREATE TABLE `frames` (
	`id` text(36) PRIMARY KEY NOT NULL,
	`parent_frame_id` text(36),
	`root_frame_id` text(36),
	`agent_name` text(255) NOT NULL,
	`status` text(50) NOT NULL,
	`input_data` text,
	`output_data` text,
	`context_data` text,
	`model` text(255),
	`effort` text(20),
	`input_tokens` integer,
	`output_tokens` integer,
	`total_cost` real,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	`completed_at` integer,
	`project_id` text(255),
	`name` text(255),
	`conversation_type` text(50) NOT NULL,
	`artifact_id` text(36),
	`task_summary` text,
	`mentioned_artifact_ids` text,
	`specialists_used` text,
	`is_hidden` integer, status_description text, compute_enabled TEXT, `delegate_name` text(255), `cache_read_tokens` integer, `cache_write_tokens` integer, `last_user_message_at` integer, last_extract_msg_idx integer, `root_seq` integer DEFAULT 0 NOT NULL, `aux_input_tokens` integer, `aux_output_tokens` integer, `aux_cache_read_tokens` integer, `aux_cache_write_tokens` integer, `aux_cost` real, `token_class_usage` text, `starred_at` integer, `compute_route` text,
	FOREIGN KEY (`parent_frame_id`) REFERENCES `frames`(`id`) ON UPDATE no action ON DELETE set null,
	FOREIGN KEY (`root_frame_id`) REFERENCES `frames`(`id`) ON UPDATE no action ON DELETE set null,
	FOREIGN KEY (`project_id`) REFERENCES `projects`(`id`) ON UPDATE no action ON DELETE cascade
)
"""#,
#"""
CREATE TABLE `projects` (
	`id` text(255) PRIMARY KEY NOT NULL,
	`name` text(255),
	`description` text,
	`context` text,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	`user_id` text(255),
	`uploads_frame_id` text(36), `memory_enabled` integer, `archived_at` integer, `artifacts_rev` integer DEFAULT 0 NOT NULL, `default_use_case_id` text,
	FOREIGN KEY (`uploads_frame_id`) REFERENCES `frames`(`id`) ON UPDATE no action ON DELETE set null
)
"""#,
    ]

    /// Every index of the four tables, by name.
    static let indexes: [(name: String, sql: String)] = [
(#"ix_artifact_versions_artifact_id"#, #"""
CREATE INDEX `ix_artifact_versions_artifact_id` ON `artifact_versions` (`artifact_id`)
"""#),
(#"ix_artifact_versions_artifact_version_id"#, #"""
CREATE INDEX `ix_artifact_versions_artifact_version_id` ON `artifact_versions` (`artifact_id`,`version_number`,`id`)
"""#),
(#"ix_artifact_versions_checksum"#, #"""
CREATE INDEX `ix_artifact_versions_checksum` ON `artifact_versions` (`checksum`,`size_bytes`)
"""#),
(#"ix_artifact_versions_env_snapshot_hash"#, #"""
CREATE INDEX `ix_artifact_versions_env_snapshot_hash` ON `artifact_versions` (`env_snapshot_hash`)
"""#),
(#"ix_artifact_versions_frame_id"#, #"""
CREATE INDEX `ix_artifact_versions_frame_id` ON `artifact_versions` (`frame_id`)
"""#),
(#"ix_artifact_versions_lineage_snapshot_hash"#, #"""
CREATE INDEX `ix_artifact_versions_lineage_snapshot_hash` ON `artifact_versions` (`lineage_snapshot_hash`)
"""#),
(#"ix_artifact_versions_parent_version_id"#, #"""
CREATE INDEX `ix_artifact_versions_parent_version_id` ON `artifact_versions` (`parent_version_id`)
"""#),
(#"ix_artifact_versions_slim_covering"#, #"""
CREATE INDEX `ix_artifact_versions_slim_covering` ON `artifact_versions` (`id`,`artifact_id`,`version_number`,`frame_id`,`content_type`,`size_bytes`,`checksum`,`storage_path`,`created_at`,`agent_name`,`language`,`is_intermediate`,`parent_version_id`,`lineage_snapshot_hash`,`env_snapshot_hash`,`producing_cell_id`,`is_checkpoint`)
"""#),
(#"ix_artifacts_conversation_priority"#, #"""
CREATE INDEX `ix_artifacts_conversation_priority` ON `artifacts` (`project_id`,`root_frame_id`,`priority`)
"""#),
(#"ix_artifacts_created_at"#, #"""
CREATE INDEX `ix_artifacts_created_at` ON `artifacts` (`created_at`)
"""#),
(#"ix_artifacts_folder_id"#, #"""
CREATE INDEX `ix_artifacts_folder_id` ON `artifacts` (`folder_id`)
"""#),
(#"ix_artifacts_frame_id"#, #"""
CREATE INDEX `ix_artifacts_frame_id` ON `artifacts` (`frame_id`)
"""#),
(#"ix_artifacts_is_user_upload"#, #"""
CREATE INDEX `ix_artifacts_is_user_upload` ON `artifacts` (`is_user_upload`)
"""#),
(#"ix_artifacts_latest_version_id"#, #"""
CREATE INDEX `ix_artifacts_latest_version_id` ON `artifacts` (`latest_version_id`)
"""#),
(#"ix_artifacts_project_id"#, #"""
CREATE INDEX `ix_artifacts_project_id` ON `artifacts` (`project_id`)
"""#),
(#"ix_artifacts_project_not_ephemeral"#, #"""
CREATE INDEX `ix_artifacts_project_not_ephemeral` ON `artifacts` (`project_id`) WHERE is_ephemeral = 0
"""#),
(#"ix_artifacts_root_frame_id"#, #"""
CREATE INDEX `ix_artifacts_root_frame_id` ON `artifacts` (`root_frame_id`)
"""#),
(#"ix_frames_agent_name"#, #"""
CREATE INDEX `ix_frames_agent_name` ON `frames` (`agent_name`)
"""#),
(#"ix_frames_artifact_id"#, #"""
CREATE INDEX `ix_frames_artifact_id` ON `frames` (`artifact_id`)
"""#),
(#"ix_frames_bench_name_search"#, #"""
CREATE INDEX `ix_frames_bench_name_search`
    ON `frames` (`project_id`,`name`,`task_summary`,`updated_at`,`agent_name`,`is_hidden`,`id`)
    WHERE parent_frame_id IS NULL AND task_summary IS NOT NULL
"""#),
(#"ix_frames_created_at"#, #"""
CREATE INDEX `ix_frames_created_at` ON `frames` (`created_at`)
"""#),
(#"ix_frames_parent_frame_id"#, #"""
CREATE INDEX `ix_frames_parent_frame_id` ON `frames` (`parent_frame_id`)
"""#),
(#"ix_frames_project_id"#, #"""
CREATE INDEX `ix_frames_project_id` ON `frames` (`project_id`)
"""#),
(#"ix_frames_project_task_summary"#, #"""
CREATE INDEX `ix_frames_project_task_summary` ON `frames` (`project_id`,`updated_at`) WHERE task_summary IS NOT NULL
"""#),
(#"ix_frames_root_by_project"#, #"""
CREATE INDEX `ix_frames_root_by_project` ON `frames` (`project_id`,`created_at`) WHERE parent_frame_id IS NULL
"""#),
(#"ix_frames_root_frame_id"#, #"""
CREATE INDEX `ix_frames_root_frame_id` ON `frames` (`root_frame_id`)
"""#),
(#"ix_frames_root_seq"#, #"""
CREATE INDEX `ix_frames_root_seq` ON `frames` (`root_frame_id`,`root_seq`)
"""#),
(#"ix_frames_root_updated"#, #"""
CREATE INDEX `ix_frames_root_updated` ON `frames` (`root_frame_id`,`updated_at`)
"""#),
(#"ix_frames_status"#, #"""
CREATE INDEX `ix_frames_status` ON `frames` (`status`)
"""#),
(#"ix_frames_status_updated"#, #"""
CREATE INDEX `ix_frames_status_updated` ON `frames` (`status`,`updated_at`)
"""#),
(#"ix_frames_updated_at"#, #"""
CREATE INDEX `ix_frames_updated_at` ON `frames` (`updated_at`)
"""#),
(#"ix_frames_vroot_cost"#, #"""
CREATE INDEX `ix_frames_vroot_cost`
  ON `frames` (coalesce(`root_frame_id`, `id`), `updated_at`, `total_cost`, `aux_cost`)
"""#),
(#"ix_projects_uploads_frame_id"#, #"""
CREATE INDEX `ix_projects_uploads_frame_id` ON `projects` (`uploads_frame_id`)
"""#),
(#"ix_projects_user_id"#, #"""
CREATE INDEX `ix_projects_user_id` ON `projects` (`user_id`)
"""#),
(#"ix_projects_user_updated"#, #"""
CREATE INDEX `ix_projects_user_updated` ON `projects` (`user_id`,`updated_at`)
"""#),
(#"uq_artifact_versions_artifact_version"#, #"""
CREATE UNIQUE INDEX `uq_artifact_versions_artifact_version` ON `artifact_versions` (`artifact_id`,`version_number`)
"""#),
    ]
}

/// A made-up database with Find's four tables in full, in a temporary folder.
/// Every column Find must never return holds a SECRET marker.
struct FindDatabase {
    let dir: URL
    let url: URL

    /// `indexes: false` is a database without the two indexes Find may hint at
    /// (and without all the others): the least the reads need.
    init(indexes: Bool = true) throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("bench-find-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("made-up.db")
        try run((FindSchema.tables + (indexes ? FindSchema.indexes.map(\.sql) : [])).map { $0 + ";" }.joined(separator: "\n"))
    }

    func remove() { try? FileManager.default.removeItem(at: dir) }

    /// Runs SQL against the file, read-write: for building it only.
    func run(_ sql: String) throws {
        let make = Process()
        make.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        make.arguments = [url.path]
        let input = Pipe()
        make.standardInput = input
        make.standardOutput = FileHandle.nullDevice
        try make.run()
        input.fileHandleForWriting.write(Data(sql.utf8))
        try input.fileHandleForWriting.close()
        make.waitUntilExit()
        #expect(make.terminationStatus == 0)
    }

    private static func q(_ text: String?) -> String { MadeUpDatabase.quote(text) }

    func project(_ id: String, _ name: String) throws {
        try run("INSERT INTO projects(id, name, created_at, updated_at, description) VALUES (\(Self.q(id)), \(Self.q(name)), 1, 1, 'SECRET-DESCRIPTION');")
    }

    /// A root session, or (with `parent`) a sub-agent frame of one.
    func session(_ id: String, project: String = "proj_a", title: String? = "Made-up session", parent: String? = nil,
                 hidden: Bool = false, agent: String = "OPERON", type: String = "chat", summary: String? = "SECRET-SUMMARY",
                 updated: Int64 = 1_791_800_000_000) throws {
        try run("""
            INSERT INTO frames(id, parent_frame_id, root_frame_id, agent_name, status, input_data, output_data, created_at, updated_at,
                project_id, name, conversation_type, task_summary, is_hidden)
            VALUES (\(Self.q(id)), \(Self.q(parent)), \(Self.q(parent)), \(Self.q(agent)), 'completed', 'SECRET-INPUT', 'SECRET-OUTPUT',
                \(updated), \(updated), \(Self.q(project)), \(Self.q(title)), \(Self.q(type)), \(Self.q(summary)), \(hidden ? 1 : 0));
            """)
    }

    /// An artifact with `versions` versions, the last made at `at`
    /// (milliseconds), a minute apart. Returns the ids of its versions.
    @discardableResult
    func file(_ name: String, in session: String, project: String = "proj_a", at: Int64, versions: Int = 1, mime: String = "image/png",
              size: Int = 1_000, intermediate: Bool = false, priority: String = "unknown", upload: Bool = false,
              ephemeral: Bool = false, id: Int) throws -> [String] {
        let artifact = madeUpID(0x1000 + id)
        var ids: [String] = []
        var sql = ""
        for n in 1...versions {
            let version = madeUpID(0x2000 + id * 10 + n)
            ids.append(version)
            let time = at - Int64(versions - n) * 60_000
            // Only the last version's `is_intermediate` is the one Find looks at.
            sql += """
                INSERT INTO artifact_versions(id, artifact_id, version_number, frame_id, content_type, size_bytes, checksum, storage_path,
                    created_at, extracted_code, is_intermediate)
                VALUES (\(Self.q(version)), \(Self.q(artifact)), \(n), \(Self.q(session)), \(Self.q(mime)), \(size), 'SECRET-CHECKSUM',
                    'SECRET-PATH', \(time), 'SECRET-CODE', \(n == versions && intermediate ? 1 : 0));

                """
        }
        sql += """
            INSERT INTO artifacts(id, project_id, root_frame_id, frame_id, filename, created_at, latest_version_id, is_user_upload,
                is_ephemeral, sort_order, priority)
            VALUES (\(Self.q(artifact)), \(Self.q(project)), \(Self.q(session)), \(Self.q(session)), \(Self.q(name)), \(at - 1_000),
                \(Self.q(ids.last)), \(upload ? 1 : 0), \(ephemeral ? 1 : 0), 0, \(Self.q(priority)));
            """
        try run(sql)
        return ids
    }

    /// The version id of file `id`'s `n`th version.
    static func version(_ id: Int, _ n: Int = 1) -> String { madeUpID(0x2000 + id * 10 + n) }
}

/// A moment, in milliseconds: 2026-10-23 12:00 UTC plus `minutes`.
func findMoment(minutes: Int = 0) -> Int64 { 1_792_756_800_000 + Int64(minutes) * 60_000 }

/// Capsid's own source, as text, for the tests that hold the wiring.
enum FindRepo {
    /// This checkout: Tests/BenchTests/<this file> → the root.
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func source(_ relative: String) -> String {
        (try? String(contentsOf: root.appendingPathComponent("Sources/Bench/\(relative)"), encoding: .utf8)) ?? ""
    }
}
