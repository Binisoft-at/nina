import NinaCore

// The ⓘ texts of Import & Export (InfoButton): a title and one or two plain sentences each, in one
// place so they stay true to the import rules (docs/IMPORT.md, docs/HEALTH.md).

enum ImportInfo {
    // MARK: Prompts and formats

    static let setupTitle = "Setup prompt"
    static let setup = "One prompt for any AI: it writes your goals & plan, foods, meals & recipes and, if you give them, "
        + "past weigh-ins and measurements in one answer. It carries your current settings and the names of your foods "
        + "and recipes, so the AI changes only what you tell it."

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
            "Give the AI your dishes with their ingredients and amounts. Ingredients without calories are looked up by "
                + "name; a dish with one Nina can't find isn't saved, so its calories are never too low."
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
            return "Each line is a weigh-in, a tape session or a body-fat value that Import adds; values Nina already "
                + "has are skipped. Orange text says what can't be used as written and what happens to it."
        }
        return "Each line says what Import does: new adds it, update changes only what the file changed, same leaves "
            + "it. Orange text says what can't be used as written and what happens to it."
    }

    static let settingsPreview = "Each line shows old → new, grouped like your plan; only what is listed changes, and an "
        + "orange “removed” means the file no longer has that item. Read the orange notes at the top first: rows Nina "
        + "couldn't use, or things to check."

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

    static let backupTitle = "Back up & restore"
    static let backup = "Back Up Everything saves all your Nina data – also what the CSV exports leave out – in one folder "
        + "you keep, where a deletion synced through iCloud can't reach it. Restore from Backup adds only what is missing."

    static let restoreTitle = "Restore"
    static let restore = "Only what Nina doesn't have is added; anything already here stays as it is, even if it changed "
        + "since, so an older backup never overwrites newer data. Things in Recently Deleted count as here – bring them "
        + "back from there."

    static let autoBackupTitle = "Automatic backup"

    /// Where the weekly backups go, how many stay and Choose Folder…
    @MainActor
    static var autoBackup: String {
        #if os(macOS)
        let place = "in \(ImportAutoBackup.ownFolderTitle) (Show in Finder)"
        #else
        let place = "in Files → \(ImportAutoBackup.ownFolderTitle)"
        #endif
        return "When this is on, Nina saves a full backup once a week by itself and keeps the last "
            + "\(BackupSchedule.keep) – \(place). Choose Folder… puts them in iCloud Drive or any folder you like."
    }

    static let exportTitle = "CSV export"
    static let export = "One file per format, to edit in Numbers or Excel and import again, or to hand to an AI. Photos, "
        + "water, routines, check-ins and the day types and checks of your days aren't in them – Back Up Everything "
        + "keeps everything."
}
