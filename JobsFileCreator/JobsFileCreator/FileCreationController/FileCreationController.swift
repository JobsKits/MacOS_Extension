//
//  FileCreationController.swift
//  JobsFileCreator
//
//  Created by Jobs on 2026年10月29日，星期四.
//

import AppKit

struct FileCreationController {

    var askName: (URL, String, String?) -> String? = FileCreatorInterface.askName
    var reveal: (URL) -> Void = { url in
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    var createFile: (String, URL) throws -> URL = { name, directory in
        return try FileCreationService().create(name: name,
                                                 in: directory)
    }

    func run(in directory: URL) {
        var name = "未命名.txt"
        var errorMessage: String?
        while let entered = askName(directory, name, errorMessage) {
            name = entered
            do {
                let url = try createFile(entered, directory)
                reveal(url)
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
