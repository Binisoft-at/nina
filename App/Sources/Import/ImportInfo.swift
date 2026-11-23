import NinaCore

// The ⓘ texts of Import & Export (InfoButton): a title and one or two plain sentences each, in one
// place so they stay true to the import rules (docs/IMPORT.md, docs/HEALTH.md).

enum ImportInfo {
    // MARK: Prompts and formats

    static let setupTitle = "Setup prompt"
    static let setup = "One prompt that has any AI write your goals & plan, foods, meals & recipes and (if you give them) "
        + "past weigh-ins in one answer. Paste the whole answer under Import – a preview shows everything first."

    /// What to give the AI for each format, and what importing it does.
    static func format(_ kind: ImportKind) -> String {
        switch kind {
        case .settings:
            "Give the AI a few lines about you – age, height, weight, goal, training, meal times – or a nutrition plan you "
                + "already have. Only the settings in its answer change, and the preview lists each one."
        case .foods:
            "Give the AI label photos, product names or another app's food list. Values are per 100 g (100 ml for drinks); "
                + "a food you already have is updated, not added twice."
        case .diary:
            "Give the AI another app's export or notes of what you ate. Rows without calories are looked up by name; "
                + "ones Nina can't find are skipped."
        case .recipes:
            "Give the AI your dishes with their ingredients and amounts. One with an ingredient Nina can't find isn't "
                + "saved, so its calories are never too low."
        case .measurements:
            "Give the AI an old spreadsheet, another app's export or a DEXA, InBody or 3D-scan report – a photo works. "
                + "Values Nina already has are skipped, so importing twice adds nothing."
        }
    }

    static let importTitle = "Prompt and answer"
    static let importText = "The prompt tells any AI exactly how to write the file so Nina can read it. Give it your data, "
        + "then paste its whole answer here (several blocks at once are fine) or choose the file it made."

    static let unrecognisedTitle = "Not recognised"
    static let unrecognised = "Nina tells the formats apart by each block's first line, the header the prompt asks for. "
        + "Ask your AI to write that block again with its header, then paste it here."

    // MARK: Preview and Undo

    static let previewTitle = "Preview"

    /// The preview of a foods, diary, meals & recipes or weight & body file.
    static func preview(_ kind: ImportKind) -> String {
        if kind == .measurements {
            return "Each line is something Import adds: a weigh-in, a tape session or a body-fat value. Values Nina "
                + "already has are skipped; orange lines can't be read and are left out."
        }
        return "Each line says what Import does: new adds it, update changes only what the file changed, same leaves "
            + "it. Orange lines can't be used as written and are left out."
    }

    static let settingsPreview = "Each line shows old → new, grouped like your plan; only what is listed changes. Orange "
        + "notes at the top are worth a look first: rows Nina couldn't use, or things to check, like macros that don't "
        + "match the calories."

    static let bodyValuesTitle = "Body values"
    static let bodyValues = "Saved as today's measurements, so your next ones show the change since then. Switch off any "
        + "that aren't from today – past values belong in the Weight & Body format, with their dates."

    static let healthTitle = "Apple Health"
    static let health = "Nina writes eaten entries of the last 14 days to Apple Health. If another app already put these "
        + "meals there, writing them again would count them twice."

    static let undoTitle = "Undo"
    static let undo = "The message after importing has Undo: it takes the whole import back. New things go to Recently "
        + "Deleted, changed ones get their old values."

    // MARK: Backup and export

    static let backupTitle = "Back Up & Restore"
    static let backup = "Back Up Everything saves all your Nina data in one folder you keep – a deletion synced through "
        + "iCloud can't reach it. Restore from Backup adds only what is missing; your records stay as they are."

    static let restoreTitle = "Restore"
    static let restore = "Only what Nina doesn't have yet is added. Anything already here stays as it is, even if it "
        + "changed since – so an older backup never overwrites newer data."

    static let autoBackupTitle = "Automatic backup"

    /// Where the weekly backups go, how many stay and Choose Folder…
    @MainActor
    static var autoBackup: String {
        #if os(macOS)
        let place = "in \(ImportAutoBackup.ownFolderTitle) (Show in Finder)"
        #else
        let place = "in Files → \(ImportAutoBackup.ownFolderTitle)"
        #endif
        return "When this is on, Nina saves a full backup once a week by itself and keeps the last 4 – \(place). "
            + "Choose Folder… puts them in iCloud Drive or any folder you like."
    }

    static let exportTitle = "CSV export"
    static let export = "One file per format, to edit in Numbers or Excel and import again, or to hand to an AI. Photos, "
        + "water, check-ins and routines aren't in them – Back Up Everything keeps everything."
}
