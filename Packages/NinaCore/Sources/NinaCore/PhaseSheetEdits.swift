import Foundation

// Saving the phase sheet without undoing what changed meanwhile: the sheet copies the phase
// when it opens, and while it is open a check-in Apply can add a revision, a Start can start the
// phase, or an edit can arrive from another device. Save takes the phase as stored now and
// changes only the fields the person changed in the sheet.

extension CoachPlan.Phase {
    /// This phase (as stored now) with the sheet's edits: every field the sheet edits whose value
    /// in `edited` differs from `original` (what the sheet showed when it opened) is taken from
    /// `edited`; everything else stays as stored. The revisions, `startedAt`, `status` and
    /// `startWeight` always stay (Calculate, Start Now and Mark as Done change them on their own).
    /// The rate and the review checkpoint move as pairs, so their low end never passes the high
    /// one. Unchanged edits give this phase back unchanged.
    public func applyingPhaseSheetEdits(original: CoachPlan.Phase, edited: CoachPlan.Phase) -> CoachPlan.Phase {
        var result = self
        if edited.name != original.name { result.name = edited.name }
        if edited.goal != original.goal { result.goal = edited.goal }
        if edited.start != original.start { result.start = edited.start }
        if edited.startApprox != original.startApprox { result.startApprox = edited.startApprox }
        if edited.end != original.end { result.end = edited.end }
        if edited.endApprox != original.endApprox { result.endApprox = edited.endApprox }
        if edited.rateMin != original.rateMin || edited.rateMax != original.rateMax {
            result.rateMin = edited.rateMin
            result.rateMax = edited.rateMax
        }
        if edited.reviewMin != original.reviewMin || edited.reviewMax != original.reviewMax {
            result.reviewMin = edited.reviewMin
            result.reviewMax = edited.reviewMax
        }
        if edited.targetWeight != original.targetWeight { result.targetWeight = edited.targetWeight }
        if edited.targetBodyFat != original.targetBodyFat { result.targetBodyFat = edited.targetBodyFat }
        if edited.maxWaistGainCm != original.maxWaistGainCm { result.maxWaistGainCm = edited.maxWaistGainCm }
        if edited.bodyFatCeiling != original.bodyFatCeiling { result.bodyFatCeiling = edited.bodyFatCeiling }
        if edited.note != original.note { result.note = edited.note }
        return result
    }
}
