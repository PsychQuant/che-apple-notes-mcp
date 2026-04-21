import Testing
@testable import CheAppleNotesMCP

@Suite struct FolderHierarchyTests {

    private func folder(
        pk: Int64,
        title: String,
        parent: Int64? = nil,
        account: String? = "iCloud",
        hidden: Bool = false,
        sortOrder: Int? = nil,
        shared: Bool = false
    ) -> Folder {
        Folder(
            pk: pk,
            identifier: "folder-\(pk)",
            title: title,
            accountPK: 1,
            accountName: account,
            parentPK: parent,
            isHiddenContainer: hidden,
            sortOrder: sortOrder,
            shared: shared
        )
    }

    @Test func buildTreeReturnsRootWhenFlat() {
        let nodes = FolderHierarchy.buildTree([
            folder(pk: 1, title: "A"),
            folder(pk: 2, title: "B")
        ])
        #expect(nodes.count == 2)
        #expect(nodes.allSatisfy { $0.children.isEmpty })
        #expect(nodes.map { $0.folder.title } == ["A", "B"])
    }

    @Test func buildTreeNestsChildrenByParentPK() {
        let nodes = FolderHierarchy.buildTree([
            folder(pk: 1, title: "Root"),
            folder(pk: 2, title: "Child", parent: 1),
            folder(pk: 3, title: "Grandchild", parent: 2)
        ])
        #expect(nodes.count == 1)
        #expect(nodes[0].folder.title == "Root")
        #expect(nodes[0].children.count == 1)
        #expect(nodes[0].children[0].folder.title == "Child")
        #expect(nodes[0].children[0].children[0].folder.title == "Grandchild")
    }

    @Test func orphanedFoldersBecomeRoots() {
        // Parent 999 is not present → folder becomes a root
        let nodes = FolderHierarchy.buildTree([
            folder(pk: 1, title: "Orphan", parent: 999),
            folder(pk: 2, title: "Standalone")
        ])
        #expect(nodes.count == 2)
        #expect(Set(nodes.map { $0.folder.title }) == Set(["Orphan", "Standalone"]))
    }

    @Test func childrenSortBySortOrderThenTitle() {
        let nodes = FolderHierarchy.buildTree([
            folder(pk: 1, title: "Root"),
            folder(pk: 2, title: "B child", parent: 1, sortOrder: 2),
            folder(pk: 3, title: "A child", parent: 1, sortOrder: 1),
            folder(pk: 4, title: "C child", parent: 1, sortOrder: 2)
        ])
        let kids = nodes[0].children.map { $0.folder.title }
        #expect(kids == ["A child", "B child", "C child"])
    }

    @Test func buildByAccountGroupsByAccountName() {
        let results = FolderHierarchy.buildByAccount(folders: [
            folder(pk: 1, title: "iNote", account: "iCloud"),
            folder(pk: 2, title: "LNote", account: "On My Mac"),
            folder(pk: 3, title: "iNote2", account: "iCloud")
        ])
        #expect(results.count == 2)
        #expect(results.map { $0.accountName } == ["On My Mac", "iCloud"])

        let iCloud = results.first { $0.accountName == "iCloud" }
        #expect(iCloud?.roots.count == 2)
    }

    @Test func buildByAccountFiltersHiddenContainers() {
        let results = FolderHierarchy.buildByAccount(folders: [
            folder(pk: 1, title: "visible"),
            folder(pk: 2, title: "hidden", hidden: true)
        ])
        let names = results.flatMap { $0.roots.map { $0.folder.title } }
        #expect(names == ["visible"])
    }

    @Test func buildByAccountDefaultsUnknownAccountName() {
        let results = FolderHierarchy.buildByAccount(folders: [
            folder(pk: 1, title: "Lost", account: nil)
        ])
        #expect(results.count == 1)
        #expect(results[0].accountName == "(unknown)")
    }
}
