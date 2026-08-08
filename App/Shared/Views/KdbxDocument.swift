import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var kdbx: UTType {
        UTType(filenameExtension: "kdbx") ?? .data
    }
}

/// Wrapper minimo per poter usare `.fileExporter`/`.fileImporter` di SwiftUI
/// con i byte grezzi del vault.
struct KdbxDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.kdbx, .data] }
    static var writableContentTypes: [UTType] { [.kdbx] }

    var bytes: [UInt8]

    init(bytes: [UInt8] = []) {
        self.bytes = bytes
    }

    init(configuration: ReadConfiguration) throws {
        bytes = Array(configuration.file.regularFileContents ?? Data())
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(bytes))
    }
}
