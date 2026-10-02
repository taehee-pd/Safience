import XCTest
#if canImport(Compression)
import Compression
#endif
@testable import PadCore

final class BookmarkFileTests: XCTestCase {
    // As Chrome writes it: everything in one list, the bar marked as the
    // personal toolbar folder, icons inline.
    let chrome = """
    <!DOCTYPE NETSCAPE-Bookmark-file-1>
    <!-- This is an automatically generated file.
         It will be read and overwritten.
         DO NOT EDIT! -->
    <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
    <TITLE>Bookmarks</TITLE>
    <H1>Bookmarks</H1>
    <DL><p>
        <DT><H3 ADD_DATE="1700000000" LAST_MODIFIED="1700000001" PERSONAL_TOOLBAR_FOLDER="true">Bookmarks bar</H3>
        <DL><p>
            <DT><A HREF="https://www.figma.com/files" ADD_DATE="1700000002" ICON="data:image/png;base64,iVBORw0KGgo=">Figma</A>
            <DT><H3 ADD_DATE="1700000003">Design &amp; Docs</H3>
            <DL><p>
                <DT><A HREF="https://www.notion.so/">Notion</A>
                <DT><A HREF="javascript:alert(1)">A bookmarklet</A>
            </DL><p>
            <DT><H3>Empty</H3>
            <DL><p>
            </DL><p>
        </DL><p>
        <DT><H3>Other bookmarks</H3>
        <DL><p>
            <DT><A HREF="https://app.slack.com/client">Slack &#8212; the
              team</A>
        </DL><p>
        <DT><a href='https://linear.app/'>Linear</a>
    </DL><p>
    """

    // As Safari writes it, in Bookmarks.html of its export: no list around
    // the folders, Favorites named rather than marked.
    let safari = """
    <!DOCTYPE NETSCAPE-Bookmark-file-1>
    <HTML>
    <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
    <Title>Bookmarks</Title>
    <H1>Bookmarks</H1>
    <DT><H3 FOLDED>Favorites</H3>
    <DL><p>
    <DT><A HREF="https://www.apple.com/">Apple</A>
    </DL><p>
    <DT><H3 id="com.apple.ReadingList" FOLDED>Reading List</H3>
    <DL><p>
    <DT><A HREF="https://webkit.org/blog/">WebKit Blog</A>
    </DL><p>
    </HTML>
    """

    func testChromesBarComesFirstAndItsFoldersKeepTheirShape() {
        let read = BookmarkFile.parse(Data(chrome.utf8))
        XCTAssertEqual(read.items.map(\.label), ["Figma", "Design & Docs", "Other bookmarks", "Linear"])
        XCTAssertEqual(read.items[1].children?.map(\.label), ["Notion"], "javascript: is left out")
        XCTAssertEqual(read.items[2].children?.first?.label, "Slack — the team", "entities decoded, spaces tidied")
        XCTAssertEqual(read.items[3].url?.absoluteString, "https://linear.app/")
        XCTAssertEqual(read.count, 4)
        XCTAssertEqual(read.icons["figma.com"], Data(base64Encoded: "iVBORw0KGgo="))
    }

    func testSafarisFavoritesComeFirst() {
        let read = BookmarkFile.parse(Data(safari.utf8))
        XCTAssertEqual(read.items.map(\.label), ["Apple", "Reading List"])
        XCTAssertEqual(read.items[1].children?.first?.url?.absoluteString, "https://webkit.org/blog/")
        XCTAssertTrue(read.icons.isEmpty)
    }

    func testNothingUsableIsNothing() {
        XCTAssertTrue(BookmarkFile.parse(Data()).items.isEmpty)
        XCTAssertTrue(BookmarkFile.parse(Data("<html><body>Not bookmarks</body></html>".utf8)).items.isEmpty)
        XCTAssertTrue(BookmarkFile.parse(Data("<DL><DT><A HREF=\"file:///etc/hosts\">x</A>".utf8)).items.isEmpty)
    }

    func testImportingTheSameFileTwiceAddsNothing() {
        let read = BookmarkFile.parse(Data(chrome.utf8))
        var space: [Bookmark] = []
        XCTAssertEqual(Bookmarks.merge(read.items, into: &space), 4)
        XCTAssertEqual(Bookmarks.merge(read.items, into: &space), 0)
        XCTAssertEqual(space.count, 4)
    }

    func testAFolderOfTheSameNameIsMergedInto() throws {
        var space = [Bookmark(folder: "Design & Docs", children: [
            Bookmark(title: "Notion", url: try XCTUnwrap(URL(string: "https://www.notion.so"))),
        ])]
        let read = BookmarkFile.parse(Data(chrome.utf8))
        XCTAssertEqual(Bookmarks.merge(read.items, into: &space), 3, "Notion was there already")
        XCTAssertEqual(space.first?.children?.count, 1)
    }

    // MARK: Safari's export, a ZIP

    func testTheBookmarksComeOutOfAStoredArchive() throws {
        let content = Array(safari.utf8)
        let archive = zip("Safari Export/Bookmarks.html", content, method: 0, packed: content)
        XCTAssertTrue(ZipFile.isArchive(archive))
        XCTAssertEqual(ZipFile.names(in: archive), ["Safari Export/Bookmarks.html"])
        let file = try XCTUnwrap(ZipFile.file(in: archive) { $0.hasSuffix("Bookmarks.html") })
        XCTAssertEqual(BookmarkFile.parse(file).items.map(\.label), ["Apple", "Reading List"])
        XCTAssertNil(ZipFile.file(in: archive) { $0.hasSuffix("History.json") })
        XCTAssertFalse(ZipFile.isArchive(Data(safari.utf8)))
    }

    #if canImport(Compression)
    func testADeflatedFileIsInflated() throws {
        let content = Array(String(repeating: safari, count: 20).utf8)
        var packed = [UInt8](repeating: 0, count: content.count)
        let size = compression_encode_buffer(&packed, packed.count, content, content.count, nil, COMPRESSION_ZLIB)
        XCTAssertGreaterThan(size, 0)
        let archive = zip("Bookmarks.html", content, method: 8, packed: Array(packed.prefix(size)))
        let file = try XCTUnwrap(ZipFile.file(in: archive) { $0.hasSuffix("Bookmarks.html") })
        XCTAssertEqual(file, Data(content))
    }
    #endif

    func testABrokenArchiveGivesNothing() {
        let content = Array(safari.utf8)
        let archive = zip("Bookmarks.html", content, method: 0, packed: content)
        XCTAssertNil(ZipFile.file(in: archive.prefix(40)) { _ in true })
        XCTAssertTrue(ZipFile.names(in: Data([0x50, 0x4B, 0x03, 0x04])).isEmpty)
    }

    /// One file in a ZIP, as an archiver would write it, without its CRC,
    /// which the reader doesn't check.
    private func zip(_ name: String, _ content: [UInt8], method: UInt16, packed: [UInt8]) -> Data {
        var out: [UInt8] = []
        func u16(_ value: Int) { out += [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)] }
        func u32(_ value: Int) {
            out += [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 24 & 0xFF)]
        }
        let nameBytes = Array(name.utf8)
        u32(0x0403_4B50); u16(20); u16(0); u16(Int(method)); u16(0); u16(0); u32(0)
        u32(packed.count); u32(content.count); u16(nameBytes.count); u16(0)
        out += nameBytes
        out += packed
        let central = out.count
        u32(0x0201_4B50); u16(20); u16(20); u16(0); u16(Int(method)); u16(0); u16(0); u32(0)
        u32(packed.count); u32(content.count); u16(nameBytes.count); u16(0); u16(0); u16(0); u16(0); u32(0); u32(0)
        out += nameBytes
        let size = out.count - central
        u32(0x0605_4B50); u16(0); u16(0); u16(1); u16(1); u32(size); u32(central); u16(0)
        return Data(out)
    }
}
