import AppKit
import Contacts
import Foundation

struct JSONError: Codable {
    let error: String
}

struct PermissionsPayload: Codable {
    let status: String
    let canRead: Bool
    let isLimited: Bool
}

struct ContactValuePayload: Codable {
    let label: String?
    let localizedLabel: String?
    let value: String
}

struct ContactPayload: Codable {
    let identifier: String
    let displayName: String
    let nameSource: String
    let contactType: String
    let givenName: String?
    let middleName: String?
    let familyName: String?
    let nickname: String?
    let organizationName: String?
    let matchedField: String?
    let matchedValue: String?
    let matchedLabel: String?
    let matchMethod: String?
    let phoneNumbers: [ContactValuePayload]
    let emailAddresses: [ContactValuePayload]
}

struct ContactLookupPayload: Codable {
    let query: String
    let normalizedQuery: String
    let field: String
    let matches: [ContactPayload]
}

enum HelperError: Error {
    case message(String)
}

struct ContactMatch {
    let contact: CNContact
    let matchedField: String
    let matchedValue: String
    let matchedLabel: String?
    let matchMethod: String
    let score: Int
}

struct NameMatchInput {
    let field: String
    let value: String
    let fieldScore: Int
}

@main
@MainActor
struct ContactsMCPHelperAppMain {
    static let supportedCommands: Set<String> = [
        "permissions",
        "lookup-phone",
        "lookup-email",
        "search-name",
        "get-contact"
    ]

    static let defaultMaxResults = 10
    static let maxResultsUpperBound = 25

    static func main() async {
        let rawArguments = sanitizedArguments()
        let fallbackResponsePath = responsePathFromRawArguments(rawArguments)

        do {
            initializeAppKit()
            if shouldRunInteractiveBootstrap(rawArguments) {
                let exitCode = await runInteractiveBootstrap()
                NSApp.terminate(nil)
                exit(exitCode)
            }

            let invocation = try parseInvocation(rawArguments)
            let data = try await run(command: invocation.command, options: invocation.options)
            try writeResponse(data, responsePath: invocation.responsePath)
            NSApp.terminate(nil)
            exit(0)
        } catch {
            let payload = JSONError(error: errorMessage(error))
            let data = try? encodeJSON(payload)

            if let data {
                try? writeResponse(data, responsePath: fallbackResponsePath)
            } else {
                FileHandle.standardError.write(Data("{\"error\":\"Unable to encode JSON output\"}\n".utf8))
            }

            NSApp.terminate(nil)
            exit(1)
        }
    }

    static func shouldRunInteractiveBootstrap(_ rawArguments: [String]) -> Bool {
        guard let firstArgument = rawArguments.first else {
            return true
        }

        return !supportedCommands.contains(firstArgument)
    }

    static func sanitizedArguments() -> [String] {
        let rawArguments = Array(CommandLine.arguments.dropFirst())
        var sanitized: [String] = []
        var index = 0

        while index < rawArguments.count {
            let token = rawArguments[index]

            if token.hasPrefix("-psn_") {
                index += 1
                continue
            }

            if token == "-ApplePersistenceIgnoreState" {
                index += min(2, rawArguments.count - index)
                continue
            }

            sanitized.append(token)
            index += 1
        }

        return sanitized
    }

    static func responsePathFromRawArguments(_ rawArguments: [String]) -> String? {
        var index = 0

        while index < rawArguments.count {
            if rawArguments[index] == "--response-path" {
                let nextIndex = index + 1
                if nextIndex < rawArguments.count, !rawArguments[nextIndex].hasPrefix("--") {
                    return rawArguments[nextIndex]
                }
            }

            index += 1
        }

        return nil
    }

    static func parseInvocation(_ rawArguments: [String]) throws -> (command: String, options: [String: String], responsePath: String?) {
        guard let command = rawArguments.first else {
            throw HelperError.message("Missing command. Use one of: permissions, lookup-phone, lookup-email, search-name, get-contact")
        }

        var options = try parseOptions(Array(rawArguments.dropFirst()))
        let responsePath = options.removeValue(forKey: "response-path")
        return (command, options, responsePath)
    }

    static func writeResponse(_ data: Data, responsePath: String?) throws {
        guard let responsePath, !responsePath.isEmpty else {
            guard let text = String(data: data, encoding: .utf8) else {
                throw HelperError.message("Unable to encode JSON output")
            }

            print(text)
            return
        }

        let responseURL = URL(fileURLWithPath: responsePath)
        try FileManager.default.createDirectory(
            at: responseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: responseURL, options: .atomic)
    }

    static func run(command: String, options: [String: String]) async throws -> Data {
        let store = CNContactStore()

        switch command {
        case "permissions":
            let prompt = try boolOption(options, key: "prompt", defaultValue: false)
            let payload = try await permissionsPayload(store: store, prompt: prompt)
            return try encodeJSON(payload)

        case "lookup-phone":
            try ensureReadAccess()
            let query = try requiredStringOption(options, key: "query")
            let maxResults = try maxResultsOption(options)
            let payload = try lookupPhone(store: store, query: query, maxResults: maxResults)
            return try encodeJSON(payload)

        case "lookup-email":
            try ensureReadAccess()
            let query = try requiredStringOption(options, key: "query")
            let maxResults = try maxResultsOption(options)
            let payload = try lookupEmail(store: store, query: query, maxResults: maxResults)
            return try encodeJSON(payload)

        case "search-name":
            try ensureReadAccess()
            let query = try requiredStringOption(options, key: "query")
            let maxResults = try maxResultsOption(options)
            let payload = try searchName(store: store, query: query, maxResults: maxResults)
            return try encodeJSON(payload)

        case "get-contact":
            try ensureReadAccess()
            let contactIdentifier = try requiredStringOption(options, key: "contact-identifier")
            let payload = try getContact(store: store, contactIdentifier: contactIdentifier)
            return try encodeJSON(payload)

        default:
            throw HelperError.message("Unknown command: \(command)")
        }
    }

    static func initializeAppKit() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
    }

    static func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    static func errorMessage(_ error: Error) -> String {
        if let helperError = error as? HelperError {
            switch helperError {
            case .message(let message):
                return message
            }
        }

        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }

        return String(describing: error)
    }

    static func parseOptions(_ args: [String]) throws -> [String: String] {
        var options: [String: String] = [:]
        var index = 0

        while index < args.count {
            let token = args[index]
            guard token.hasPrefix("--") else {
                throw HelperError.message("Unexpected token: \(token)")
            }

            let key = String(token.dropFirst(2))
            let nextIndex = index + 1

            if nextIndex < args.count, !args[nextIndex].hasPrefix("--") {
                options[key] = args[nextIndex]
                index += 2
            } else {
                options[key] = "true"
                index += 1
            }
        }

        return options
    }

    static func boolOption(_ options: [String: String], key: String, defaultValue: Bool) throws -> Bool {
        guard let value = options[key] else {
            return defaultValue
        }

        switch value.lowercased() {
        case "1", "true", "yes", "y":
            return true
        case "0", "false", "no", "n":
            return false
        default:
            throw HelperError.message("Invalid --\(key) value. Use true or false.")
        }
    }

    static func requiredStringOption(_ options: [String: String], key: String) throws -> String {
        guard let raw = options[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            throw HelperError.message("Missing required value for --\(key)")
        }

        return raw
    }

    static func maxResultsOption(_ options: [String: String]) throws -> Int {
        guard let raw = options["max-results"] else {
            return defaultMaxResults
        }

        guard let parsed = Int(raw), parsed > 0, parsed <= maxResultsUpperBound else {
            throw HelperError.message("Invalid --max-results value. Use an integer between 1 and \(maxResultsUpperBound).")
        }

        return parsed
    }

    static func permissionsPayload(store: CNContactStore, prompt: Bool) async throws -> PermissionsPayload {
        let currentStatus = CNContactStore.authorizationStatus(for: .contacts)

        if prompt, currentStatus == .notDetermined {
            prepareForPermissionPrompt()
            return try await requestAccessAndRefreshPermissions(store: store)
        }

        return permissionsPayload(for: currentStatus)
    }

    static func runInteractiveBootstrap() async -> Int32 {
        let store = CNContactStore()
        prepareForInteractiveLaunch()

        do {
            var payload = permissionsPayload(for: CNContactStore.authorizationStatus(for: .contacts))

            if payload.status == "not_determined" {
                payload = try await requestAccessAndRefreshPermissions(store: store)
            }

            presentBootstrapAlert(for: payload)
            return payload.canRead ? 0 : 1
        } catch {
            presentAlert(
                title: "Contacts Access Failed",
                message: """
                The helper app could not request Contacts access.

                \(errorMessage(error))
                """
            )
            return 1
        }
    }

    static func prepareForInteractiveLaunch() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func prepareForPermissionPrompt() {
        prepareForInteractiveLaunch()
    }

    static func presentBootstrapAlert(for payload: PermissionsPayload) {
        switch payload.status {
        case "authorized":
            presentAlert(
                title: "Contacts Access Ready",
                message: """
                ContactsMCPHelperApp has Contacts access.

                Return to your MCP client to search names or resolve phone numbers and email addresses against your Apple Contacts data.
                """
            )
        case "limited":
            presentAlert(
                title: "Limited Contacts Access Granted",
                message: """
                ContactsMCPHelperApp has limited Contacts access.

                Lookups will only return the contacts visible to this app. Open System Settings > Privacy & Security > Contacts if you want to broaden access, then relaunch this app.
                """
            )
        case "denied":
            presentAlert(
                title: "Contacts Access Denied",
                message: """
                Contacts access was denied for ContactsMCPHelperApp.

                Open System Settings > Privacy & Security > Contacts, enable ContactsMCPHelperApp, then relaunch this app.
                """
            )
        case "restricted":
            presentAlert(
                title: "Contacts Access Restricted",
                message: "Contacts access is restricted on this Mac for ContactsMCPHelperApp."
            )
        default:
            presentAlert(
                title: "Contacts Access Still Pending",
                message: """
                Contacts access is still not determined.

                If macOS did not show a permission prompt, relaunch ContactsMCPHelperApp directly from Finder and try again.
                """
            )
        }
    }

    static func presentAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    static func requestAccess(store: CNContactStore) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestAccess(for: .contacts) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: granted)
            }
        }
    }

    static func requestAccessAndRefreshPermissions(store: CNContactStore) async throws -> PermissionsPayload {
        do {
            _ = try await requestAccess(store: store)
        } catch {
            let updatedPayload = permissionsPayload(for: CNContactStore.authorizationStatus(for: .contacts))
            if updatedPayload.status != "not_determined" {
                return updatedPayload
            }

            throw error
        }

        return permissionsPayload(for: CNContactStore.authorizationStatus(for: .contacts))
    }

    static func permissionsPayload(for status: CNAuthorizationStatus) -> PermissionsPayload {
        switch status {
        case .authorized:
            return PermissionsPayload(status: "authorized", canRead: true, isLimited: false)
        case .limited:
            return PermissionsPayload(status: "limited", canRead: true, isLimited: true)
        case .notDetermined:
            return PermissionsPayload(status: "not_determined", canRead: false, isLimited: false)
        case .restricted:
            return PermissionsPayload(status: "restricted", canRead: false, isLimited: false)
        case .denied:
            return PermissionsPayload(status: "denied", canRead: false, isLimited: false)
        @unknown default:
            return PermissionsPayload(status: "unknown", canRead: false, isLimited: false)
        }
    }

    static func ensureReadAccess() throws {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            return
        case .notDetermined:
            throw HelperError.message("Contacts access is not determined. Run contacts_permissions with prompt=true.")
        case .restricted:
            throw HelperError.message("Contacts access is restricted for this helper app.")
        case .denied:
            throw HelperError.message("Contacts access was denied for this helper app.")
        @unknown default:
            throw HelperError.message("Contacts access is unavailable for this helper app.")
        }
    }

    static func lookupPhone(store: CNContactStore, query: String, maxResults: Int) throws -> ContactLookupPayload {
        let normalizedQuery = try sanitizePhoneQuery(query)
        let queryDigits = canonicalPhoneDigits(normalizedQuery)
        let keysToFetch = contactKeysToFetch()
        let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: normalizedQuery))
        let predicateMatches = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)

        let matches = buildPhoneMatches(
            contacts: predicateMatches,
            query: normalizedQuery,
            queryDigits: queryDigits,
            defaultMatchMethod: "predicate"
        )

        let rankedMatches: [ContactMatch]
        if matches.isEmpty {
            rankedMatches = try enumerateAllPhoneMatches(store: store, query: normalizedQuery, queryDigits: queryDigits)
        } else {
            rankedMatches = matches
        }

        let payloadMatches = uniqueSortedMatches(rankedMatches, maxResults: maxResults).map {
            payloadFromContact(
                contact: $0.contact,
                matchedField: $0.matchedField,
                matchedValue: $0.matchedValue,
                matchedLabel: $0.matchedLabel,
                matchMethod: $0.matchMethod
            )
        }

        return ContactLookupPayload(
            query: query,
            normalizedQuery: normalizedQuery,
            field: "phoneNumber",
            matches: payloadMatches
        )
    }

    static func lookupEmail(store: CNContactStore, query: String, maxResults: Int) throws -> ContactLookupPayload {
        let normalizedQuery = try sanitizeEmailQuery(query)
        let keysToFetch = contactKeysToFetch()
        let predicate = CNContact.predicateForContacts(matchingEmailAddress: normalizedQuery)
        let predicateMatches = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)

        let matches = buildEmailMatches(
            contacts: predicateMatches,
            normalizedQuery: normalizedQuery,
            defaultMatchMethod: "predicate"
        )

        let rankedMatches: [ContactMatch]
        if matches.isEmpty {
            rankedMatches = try enumerateAllEmailMatches(store: store, normalizedQuery: normalizedQuery)
        } else {
            rankedMatches = matches
        }

        let payloadMatches = uniqueSortedMatches(rankedMatches, maxResults: maxResults).map {
            payloadFromContact(
                contact: $0.contact,
                matchedField: $0.matchedField,
                matchedValue: $0.matchedValue,
                matchedLabel: $0.matchedLabel,
                matchMethod: $0.matchMethod
            )
        }

        return ContactLookupPayload(
            query: query,
            normalizedQuery: normalizedQuery,
            field: "emailAddress",
            matches: payloadMatches
        )
    }

    static func searchName(store: CNContactStore, query: String, maxResults: Int) throws -> ContactLookupPayload {
        let sanitizedQuery = try sanitizeNameQuery(query)
        let normalizedQuery = normalizedSearchText(sanitizedQuery)
        let keysToFetch = contactKeysToFetch()
        let predicate = CNContact.predicateForContacts(matchingName: sanitizedQuery)
        let predicateMatches = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
        var rankedMatches = buildNameMatches(contacts: predicateMatches, normalizedQuery: normalizedQuery)

        if Set(rankedMatches.map { $0.contact.identifier }).count < maxResults {
            let excludedIdentifiers = Set(predicateMatches.map { $0.identifier })
            rankedMatches.append(contentsOf: try enumerateAllNameMatches(
                store: store,
                normalizedQuery: normalizedQuery,
                excludingIdentifiers: excludedIdentifiers
            ))
        }

        let payloadMatches = uniqueSortedMatches(rankedMatches, maxResults: maxResults).map {
            payloadFromContact(
                contact: $0.contact,
                matchedField: $0.matchedField,
                matchedValue: $0.matchedValue,
                matchedLabel: $0.matchedLabel,
                matchMethod: $0.matchMethod
            )
        }

        return ContactLookupPayload(
            query: query,
            normalizedQuery: sanitizedQuery,
            field: "name",
            matches: payloadMatches
        )
    }

    static func getContact(store: CNContactStore, contactIdentifier: String) throws -> ContactPayload {
        do {
            let contact = try store.unifiedContact(withIdentifier: contactIdentifier, keysToFetch: contactKeysToFetch())
            return payloadFromContact(contact: contact)
        } catch {
            throw HelperError.message("Contact not found for identifier '\(contactIdentifier)'.")
        }
    }

    static func contactKeysToFetch() -> [CNKeyDescriptor] {
        [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactTypeKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
        ]
    }

    static func enumerateAllPhoneMatches(store: CNContactStore, query: String, queryDigits: String) throws -> [ContactMatch] {
        let request = CNContactFetchRequest(keysToFetch: contactKeysToFetch())
        var matches: [ContactMatch] = []

        try store.enumerateContacts(with: request) { contact, _ in
            matches.append(contentsOf: buildPhoneMatches(
                contacts: [contact],
                query: query,
                queryDigits: queryDigits,
                defaultMatchMethod: "fallback"
            ))
        }

        return matches
    }

    static func enumerateAllEmailMatches(store: CNContactStore, normalizedQuery: String) throws -> [ContactMatch] {
        let request = CNContactFetchRequest(keysToFetch: contactKeysToFetch())
        var matches: [ContactMatch] = []

        try store.enumerateContacts(with: request) { contact, _ in
            matches.append(contentsOf: buildEmailMatches(
                contacts: [contact],
                normalizedQuery: normalizedQuery,
                defaultMatchMethod: "fallback"
            ))
        }

        return matches
    }

    static func enumerateAllNameMatches(
        store: CNContactStore,
        normalizedQuery: String,
        excludingIdentifiers: Set<String>
    ) throws -> [ContactMatch] {
        let request = CNContactFetchRequest(keysToFetch: contactKeysToFetch())
        var matches: [ContactMatch] = []

        try store.enumerateContacts(with: request) { contact, _ in
            guard !excludingIdentifiers.contains(contact.identifier) else {
                return
            }

            matches.append(contentsOf: buildNameMatches(
                contacts: [contact],
                normalizedQuery: normalizedQuery
            ))
        }

        return matches
    }

    static func buildPhoneMatches(
        contacts: [CNContact],
        query: String,
        queryDigits: String,
        defaultMatchMethod: String
    ) -> [ContactMatch] {
        contacts.compactMap { contact in
            bestPhoneMatch(for: contact, query: query, queryDigits: queryDigits, defaultMatchMethod: defaultMatchMethod)
        }
    }

    static func bestPhoneMatch(
        for contact: CNContact,
        query: String,
        queryDigits: String,
        defaultMatchMethod: String
    ) -> ContactMatch? {
        var bestMatch: ContactMatch?

        for phoneNumber in contact.phoneNumbers {
            let candidateValue = phoneNumber.value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidateValue.isEmpty else {
                continue
            }

            let candidateDigits = canonicalPhoneDigits(candidateValue)
            let score = scorePhoneMatch(query: query, queryDigits: queryDigits, candidateValue: candidateValue, candidateDigits: candidateDigits)
            guard score > 0 else {
                continue
            }

            let matchMethod: String
            if score >= 400 {
                matchMethod = "exact"
            } else if defaultMatchMethod == "predicate" {
                matchMethod = "predicate"
            } else {
                matchMethod = "fallback"
            }

            let candidateMatch = ContactMatch(
                contact: contact,
                matchedField: "phoneNumber",
                matchedValue: candidateValue,
                matchedLabel: phoneNumber.label,
                matchMethod: matchMethod,
                score: score
            )

            if let existingBestMatch = bestMatch {
                if candidateMatch.score > existingBestMatch.score {
                    bestMatch = candidateMatch
                }
            } else {
                bestMatch = candidateMatch
            }
        }

        return bestMatch
    }

    static func scorePhoneMatch(query: String, queryDigits: String, candidateValue: String, candidateDigits: String) -> Int {
        if candidateValue.caseInsensitiveCompare(query) == .orderedSame {
            return 450
        }

        guard !queryDigits.isEmpty, !candidateDigits.isEmpty else {
            return 0
        }

        if candidateDigits == queryDigits {
            return 400
        }

        let minLength = min(candidateDigits.count, queryDigits.count)
        if minLength >= 7, candidateDigits.hasSuffix(queryDigits) || queryDigits.hasSuffix(candidateDigits) {
            return 200 + minLength
        }

        return 0
    }

    static func buildEmailMatches(
        contacts: [CNContact],
        normalizedQuery: String,
        defaultMatchMethod: String
    ) -> [ContactMatch] {
        contacts.compactMap { contact in
            bestEmailMatch(for: contact, normalizedQuery: normalizedQuery, defaultMatchMethod: defaultMatchMethod)
        }
    }

    static func bestEmailMatch(for contact: CNContact, normalizedQuery: String, defaultMatchMethod: String) -> ContactMatch? {
        var bestMatch: ContactMatch?

        for emailAddress in contact.emailAddresses {
            let candidateValue = String(emailAddress.value).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidateValue.isEmpty else {
                continue
            }

            let normalizedCandidate = candidateValue.lowercased()
            guard normalizedCandidate == normalizedQuery else {
                continue
            }

            let matchMethod = defaultMatchMethod == "predicate" ? "exact" : "fallback"
            let candidateMatch = ContactMatch(
                contact: contact,
                matchedField: "emailAddress",
                matchedValue: candidateValue,
                matchedLabel: emailAddress.label,
                matchMethod: matchMethod,
                score: 400
            )

            if let existingBestMatch = bestMatch {
                if candidateMatch.score > existingBestMatch.score {
                    bestMatch = candidateMatch
                }
            } else {
                bestMatch = candidateMatch
            }
        }

        return bestMatch
    }

    static func buildNameMatches(contacts: [CNContact], normalizedQuery: String) -> [ContactMatch] {
        contacts.compactMap { contact in
            bestNameMatch(for: contact, normalizedQuery: normalizedQuery)
        }
    }

    static func bestNameMatch(for contact: CNContact, normalizedQuery: String) -> ContactMatch? {
        var bestMatch: ContactMatch?

        for input in nameMatchInputs(for: contact) {
            let normalizedCandidate = normalizedSearchText(input.value)
            guard let scoredMatch = scoreNameMatch(
                normalizedQuery: normalizedQuery,
                normalizedCandidate: normalizedCandidate
            ) else {
                continue
            }

            let candidateMatch = ContactMatch(
                contact: contact,
                matchedField: input.field,
                matchedValue: input.value,
                matchedLabel: nil,
                matchMethod: scoredMatch.matchMethod,
                score: scoredMatch.score + input.fieldScore
            )

            if let existingBestMatch = bestMatch {
                if candidateMatch.score > existingBestMatch.score {
                    bestMatch = candidateMatch
                }
            } else {
                bestMatch = candidateMatch
            }
        }

        return bestMatch
    }

    static func nameMatchInputs(for contact: CNContact) -> [NameMatchInput] {
        var inputs: [NameMatchInput] = []

        if let fullName = CNContactFormatter.string(from: contact, style: .fullName).flatMap(trimmedOrNil) {
            inputs.append(NameMatchInput(field: "fullName", value: fullName, fieldScore: 60))
        }

        if let organizationName = trimmedOrNil(contact.organizationName) {
            inputs.append(NameMatchInput(field: "organizationName", value: organizationName, fieldScore: 50))
        }

        if let nickname = trimmedOrNil(contact.nickname) {
            inputs.append(NameMatchInput(field: "nickname", value: nickname, fieldScore: 45))
        }

        if let givenName = trimmedOrNil(contact.givenName) {
            inputs.append(NameMatchInput(field: "givenName", value: givenName, fieldScore: 35))
        }

        if let familyName = trimmedOrNil(contact.familyName) {
            inputs.append(NameMatchInput(field: "familyName", value: familyName, fieldScore: 35))
        }

        if let middleName = trimmedOrNil(contact.middleName) {
            inputs.append(NameMatchInput(field: "middleName", value: middleName, fieldScore: 20))
        }

        return inputs
    }

    static func scoreNameMatch(
        normalizedQuery: String,
        normalizedCandidate: String
    ) -> (score: Int, matchMethod: String)? {
        guard !normalizedQuery.isEmpty, !normalizedCandidate.isEmpty else {
            return nil
        }

        let queryTokens = searchTokens(normalizedQuery)
        let candidateTokens = searchTokens(normalizedCandidate)
        let compactQueryLength = normalizedQuery.replacingOccurrences(of: " ", with: "").count
        let scoreBonus = min(compactQueryLength, 40)

        if normalizedCandidate == normalizedQuery {
            return (500 + scoreBonus, "exact")
        }

        if queryTokens.count == 1, candidateTokens.contains(normalizedQuery) {
            return (440 + scoreBonus, "wordExact")
        }

        if normalizedCandidate.hasPrefix(normalizedQuery) {
            return (360 + scoreBonus, "prefix")
        }

        if allQueryTokensMatchCandidateTokens(
            queryTokens: queryTokens,
            candidateTokens: candidateTokens,
            matcher: { queryToken, candidateToken in
                candidateToken.hasPrefix(queryToken)
            }
        ) {
            return (320 + scoreBonus, queryTokens.count == 1 ? "wordPrefix" : "tokenPrefix")
        }

        if compactQueryLength >= 3, normalizedCandidate.contains(normalizedQuery) {
            return (240 + scoreBonus, "contains")
        }

        if compactQueryLength >= 3, allQueryTokensMatchCandidateTokens(
            queryTokens: queryTokens,
            candidateTokens: candidateTokens,
            matcher: { queryToken, candidateToken in
                candidateToken.contains(queryToken)
            }
        ) {
            return (200 + scoreBonus, "tokenContains")
        }

        return nil
    }

    static func allQueryTokensMatchCandidateTokens(
        queryTokens: [String],
        candidateTokens: [String],
        matcher: (String, String) -> Bool
    ) -> Bool {
        guard !queryTokens.isEmpty else {
            return false
        }

        var remainingTokens = candidateTokens

        for queryToken in queryTokens {
            guard let matchingIndex = remainingTokens.firstIndex(where: { matcher(queryToken, $0) }) else {
                return false
            }

            remainingTokens.remove(at: matchingIndex)
        }

        return true
    }

    static func uniqueSortedMatches(_ matches: [ContactMatch], maxResults: Int) -> [ContactMatch] {
        var bestByIdentifier: [String: ContactMatch] = [:]

        for match in matches {
            if let existing = bestByIdentifier[match.contact.identifier] {
                if match.score > existing.score {
                    bestByIdentifier[match.contact.identifier] = match
                }
            } else {
                bestByIdentifier[match.contact.identifier] = match
            }
        }

        return Array(bestByIdentifier.values)
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    let lhsName = displayName(for: lhs.contact, matchedValue: lhs.matchedValue).displayName
                    let rhsName = displayName(for: rhs.contact, matchedValue: rhs.matchedValue).displayName
                    return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
                }

                return lhs.score > rhs.score
            }
            .prefix(maxResults)
            .map { $0 }
    }

    static func payloadFromContact(
        contact: CNContact,
        matchedField: String? = nil,
        matchedValue: String? = nil,
        matchedLabel: String? = nil,
        matchMethod: String? = nil
    ) -> ContactPayload {
        let display = displayName(for: contact, matchedValue: matchedValue)

        return ContactPayload(
            identifier: contact.identifier,
            displayName: display.displayName,
            nameSource: display.nameSource,
            contactType: contactTypeString(contact.contactType),
            givenName: trimmedOrNil(contact.givenName),
            middleName: trimmedOrNil(contact.middleName),
            familyName: trimmedOrNil(contact.familyName),
            nickname: trimmedOrNil(contact.nickname),
            organizationName: trimmedOrNil(contact.organizationName),
            matchedField: matchedField,
            matchedValue: trimmedOrNil(matchedValue),
            matchedLabel: trimmedOrNil(matchedLabel),
            matchMethod: matchMethod,
            phoneNumbers: phoneNumberPayloads(contact.phoneNumbers),
            emailAddresses: emailAddressPayloads(contact.emailAddresses)
        )
    }

    static func displayName(for contact: CNContact, matchedValue: String?) -> (displayName: String, nameSource: String) {
        if let fullName = CNContactFormatter.string(from: contact, style: .fullName).flatMap(trimmedOrNil) {
            return (fullName, "fullName")
        }

        if let organizationName = trimmedOrNil(contact.organizationName) {
            return (organizationName, "organizationName")
        }

        if let nickname = trimmedOrNil(contact.nickname) {
            return (nickname, "nickname")
        }

        if let matchedValue = trimmedOrNil(matchedValue) {
            return (matchedValue, "matchedValue")
        }

        return ("Unnamed Contact", "fallback")
    }

    static func phoneNumberPayloads(_ phoneNumbers: [CNLabeledValue<CNPhoneNumber>]) -> [ContactValuePayload] {
        phoneNumbers.compactMap { phoneNumber in
            let value = phoneNumber.value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                return nil
            }

            return ContactValuePayload(
                label: trimmedOrNil(phoneNumber.label),
                localizedLabel: localizedLabel(phoneNumber.label),
                value: value
            )
        }
    }

    static func emailAddressPayloads(_ emailAddresses: [CNLabeledValue<NSString>]) -> [ContactValuePayload] {
        emailAddresses.compactMap { emailAddress in
            let value = String(emailAddress.value).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                return nil
            }

            return ContactValuePayload(
                label: trimmedOrNil(emailAddress.label),
                localizedLabel: localizedLabel(emailAddress.label),
                value: value
            )
        }
    }

    static func sanitizePhoneQuery(_ query: String) throws -> String {
        let sanitized = stripSchemes(query, prefixes: ["tel:", "sms:"])
        guard !sanitized.isEmpty else {
            throw HelperError.message("Provide a non-empty phone query.")
        }

        return sanitized
    }

    static func sanitizeEmailQuery(_ query: String) throws -> String {
        let sanitized = stripSchemes(query, prefixes: ["mailto:"]).lowercased()
        guard !sanitized.isEmpty else {
            throw HelperError.message("Provide a non-empty email query.")
        }

        return sanitized
    }

    static func sanitizeNameQuery(_ query: String) throws -> String {
        let sanitized = collapseWhitespace(query)
        guard !sanitized.isEmpty else {
            throw HelperError.message("Provide a non-empty name query.")
        }

        return sanitized
    }

    static func stripSchemes(_ value: String, prefixes: [String]) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)

        for prefix in prefixes where normalized.lowercased().hasPrefix(prefix) {
            normalized.removeFirst(prefix.count)
            normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        return normalized
    }

    static func collapseWhitespace(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func normalizedSearchText(_ value: String) -> String {
        collapseWhitespace(value)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }

    static func searchTokens(_ value: String) -> [String] {
        normalizedSearchText(value)
            .split(separator: " ")
            .map(String.init)
    }

    static func canonicalPhoneDigits(_ value: String) -> String {
        value.unicodeScalars
            .filter(CharacterSet.decimalDigits.contains)
            .map(String.init)
            .joined()
    }

    static func localizedLabel(_ label: String?) -> String? {
        guard let label else {
            return nil
        }

        return CNLabeledValue<NSString>.localizedString(forLabel: label)
    }

    static func contactTypeString(_ contactType: CNContactType) -> String {
        switch contactType {
        case .person:
            return "person"
        case .organization:
            return "organization"
        @unknown default:
            return "unknown"
        }
    }

    static func trimmedOrNil(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
