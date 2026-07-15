extension Sequence where Element: Identifiable {
    /// The elements in order, keeping the first of each distinct `id` and dropping
    /// later repeats. Used to avoid encrypting to the same key twice when it arrives
    /// from more than one place (say, an identity and the same key added via a contact).
    func deduplicated() -> [Element] {
        var seen = Set<Element.ID>()
        return filter { seen.insert($0.id).inserted }
    }
}
