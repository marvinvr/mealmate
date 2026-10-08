import Foundation

/// Display helpers for recipe metadata (times, servings, ratings) shared by cards, rows
/// and the detail screen.
enum RecipeFormatting {
    // MARK: Durations

    /// Parses Mealie's free-form time strings into minutes: ISO 8601 (`PT1H30M`),
    /// "1 hour 30 minutes", "1h 30m", "45 min", "1 Stunde 20 Minuten", "1:30", or a bare
    /// number (minutes). `nil` when nothing recognisable is found.
    static func minutes(from text: String?) -> Int? {
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let text = raw.lowercased()

        if text.hasPrefix("pt") || text.hasPrefix("p") && text.contains("t") {
            return isoMinutes(text)
        }
        if let bare = Double(text.replacingOccurrences(of: ",", with: ".")) {
            return bare > 0 ? Int(bare.rounded()) : nil
        }
        // "1:30" → 90
        let clock = text.split(separator: ":")
        if clock.count == 2, let hours = Int(clock[0]), let mins = Int(clock[1]) {
            return hours * 60 + mins
        }

        var total = 0.0
        var found = false
        let pattern = /(\d+(?:[.,]\d+)?)\s*([a-zäöü]+)?/
        for match in text.matches(of: pattern) {
            guard let value = Double(match.1.replacingOccurrences(of: ",", with: ".")) else { continue }
            let unit = match.2.map(String.init) ?? ""
            if unit.hasPrefix("d") || unit.hasPrefix("tag") {
                total += value * 24 * 60
            } else if unit.hasPrefix("h") || unit.hasPrefix("std") || unit.hasPrefix("stu") {
                total += value * 60
            } else if unit.hasPrefix("m") || unit.isEmpty {
                total += value
            } else if unit.hasPrefix("s") {
                total += value / 60
            } else {
                continue
            }
            found = true
        }
        guard found, total > 0 else { return nil }
        return max(1, Int(total.rounded()))
    }

    private static func isoMinutes(_ text: String) -> Int? {
        var total = 0.0
        var found = false
        var number = ""
        var inTime = false
        for character in text.dropFirst() {
            if character == "t" { inTime = true; continue }
            if character.isNumber || character == "." || character == "," {
                number.append(character == "," ? "." : character)
                continue
            }
            guard let value = Double(number) else { number = ""; continue }
            switch character {
            case "d": total += value * 24 * 60
            case "h": total += value * 60
            case "m" where inTime: total += value
            case "s": total += value / 60
            default: break
            }
            found = true
            number = ""
        }
        guard found, total > 0 else { return nil }
        return max(1, Int(total.rounded()))
    }

    /// "45 min", "1 hr, 30 min". Unparseable input is returned as entered.
    static func duration(_ text: String?) -> String? {
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        guard let minutes = minutes(from: raw) else { return raw }
        return duration(minutes: minutes)
    }

    static func duration(minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// Spoken form for VoiceOver: "1 hour, 30 minutes".
    static func spokenDuration(_ text: String?) -> String? {
        guard let minutes = minutes(from: text) else { return text }
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    /// The most useful single time for a card: total, else prep + cook, else whichever exists.
    static func headlineTime(total: String?, prep: String?, cook: String?, perform: String?) -> String? {
        if let total = duration(total) { return total }
        let prepMinutes = minutes(from: prep)
        let cookMinutes = minutes(from: cook) ?? minutes(from: perform)
        if let prepMinutes, let cookMinutes { return duration(minutes: prepMinutes + cookMinutes) }
        return duration(prep) ?? duration(cook) ?? duration(perform)
    }

    // MARK: Servings & ratings

    /// "4 servings", "1 serving", "2.5 servings".
    static func servings(_ value: Double?) -> String? {
        guard let value, value > 0 else { return nil }
        let number = value.formatted(.number.precision(.fractionLength(0...1)))
        return value == 1 ? "\(number) serving" : "\(number) servings"
    }

    /// "4.5" (one decimal at most) for ratings 1–5.
    static func rating(_ value: Double?) -> String? {
        guard let value, value > 0 else { return nil }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

extension RecipeSummary {
    /// Time shown on cards and rows.
    var headlineTime: String? {
        RecipeFormatting.headlineTime(total: totalTime, prep: prepTime, cook: cookTime, perform: performTime)
    }

    /// "35 min" or "4 servings": the one fact a card shows under the title.
    var cardMetadata: String? {
        headlineTime ?? RecipeFormatting.servings(recipeServings)
    }

    /// "Lemon Herb Chicken, 35 minutes, 4 stars".
    var accessibilitySummary: String {
        var parts = [displayName]
        if let time = RecipeFormatting.headlineTime(total: totalTime, prep: prepTime, cook: cookTime, perform: performTime) {
            parts.append(RecipeFormatting.spokenDuration(time) ?? time)
        } else if let servings = RecipeFormatting.servings(recipeServings) {
            parts.append(servings)
        }
        if let rating = RecipeFormatting.rating(rating) {
            parts.append("\(rating) stars")
        }
        return parts.joined(separator: ", ")
    }
}
