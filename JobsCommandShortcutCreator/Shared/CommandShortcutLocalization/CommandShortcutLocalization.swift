//
//  CommandShortcutLocalization.swift
//  JobsCommandShortcutCreator
//
//  Created by Jobs on 2026年11月13日，星期五.
//

import AppKit

enum CommandShortcutLocalization {

    static let defaults = UserDefaults(suiteName: "com.jobs.finderextensions.managementpanel.preferences")!
    static let languages = ["zh-Hans", "zh-Hant", "bo", "en", "ja", "fr", "es", "de", "ru", "ko"]
    static let languageNames = ["简体中文", "繁體中文", "བོད་ཡིག", "English", "日本語", "Français", "Español", "Deutsch", "Русский", "한국어"]
    static let translations: [String: [String]] = [
        "title": ["创建脚本快捷入口", "建立指令稿快捷入口", "འཕྲལ་འཇུག་ཡིག་ཆ་བཟོ།", "Create Script Launcher", "スクリプト起動ファイルを作成", "Créer un lanceur de script", "Crear acceso al script", "Skriptstarter erstellen", "Создать ярлык скрипта", "스크립트 실행 파일 만들기"],
        "create": ["创建", "建立", "བཟོ།", "Create", "作成", "Créer", "Crear", "Erstellen", "Создать", "만들기"],
        "cancel": ["取消", "取消", "ཕྱིར་འཐེན།", "Cancel", "キャンセル", "Annuler", "Cancelar", "Abbrechen", "Отмена", "취소"],
        "ok": ["好", "好", "འགྲིག", "OK", "OK", "OK", "Aceptar", "OK", "ОК", "확인"],
        "suffix": ["（快捷入口）", "（快捷入口）", "（འཕྲལ་འཇུག）", " (Launcher)", "（起動）", " (Lanceur)", " (Acceso)", " (Starter)", " (Запуск)", " (실행)"],
        "prompt": ["请输入以 .command 结尾的入口名称。文件将创建在所选文件夹旁边。", "請輸入以 .command 結尾的入口名稱。檔案將建立在所選資料夾旁邊。", ".command མཇུག་ཏུ་ཡོད་པའི་མིང་འཇུག འདེམས་པའི་སྣོད་ཀྱི་འགྲམ་དུ་བཟོ།", "Enter a launcher name ending in .command. It will be created beside the selected folder.", ".command で終わる名前を入力してください。選択したフォルダと同じ階層に作成します。", "Saisissez un nom se terminant par .command. Le lanceur sera créé à côté du dossier sélectionné.", "Escriba un nombre terminado en .command. Se creará junto a la carpeta seleccionada.", "Geben Sie einen Namen mit der Endung .command ein. Die Datei wird neben dem gewählten Ordner erstellt.", "Введите имя с окончанием .command. Файл появится рядом с выбранной папкой.", ".command로 끝나는 이름을 입력하세요. 선택한 폴더 옆에 생성됩니다."],
        "invalidName": ["名称须以 .command 结尾，且不能含 /、:、换行或控制字符。", "名稱須以 .command 結尾，且不能含 /、:、換行或控制字元。", "མིང་གི་མཇུག .command དགོས། / དང་ : དང་ཚིག་ཕྲེང་གསར་པ་མི་ཆོག", "Use a valid name ending in .command, without /, :, newlines or control characters.", "名前は .command で終わり、/、:、改行、制御文字を含まないようにしてください。", "Le nom doit se terminer par .command, sans /, :, retour à la ligne ni caractère de contrôle.", "El nombre debe terminar en .command y no contener /, :, saltos de línea ni caracteres de control.", "Der Name muss auf .command enden und darf keine /, :, Zeilenumbrüche oder Steuerzeichen enthalten.", "Имя должно оканчиваться на .command и не содержать /, :, переводы строк или управляющие символы.", "이름은 .command로 끝나야 하며 /, :, 줄바꿈, 제어 문자를 포함할 수 없습니다."],
        "occupied": ["同名文件、文件夹或链接已存在，请换个名称。", "同名檔案、資料夾或連結已存在，請更換名稱。", "མིང་འདི་ཡོད་ཟིན། མིང་གཞན་ཞིག་འཇུག", "A file, folder or link with this name already exists. Choose another name.", "同名のファイル、フォルダ、リンクが存在します。別の名前を指定してください。", "Un fichier, dossier ou lien porte déjà ce nom. Choisissez un autre nom.", "Ya existe un archivo, carpeta o enlace con ese nombre. Elija otro.", "Eine Datei, ein Ordner oder Link mit diesem Namen existiert bereits. Wählen Sie einen anderen Namen.", "Файл, папка или ссылка с таким именем уже существует. Выберите другое имя.", "같은 이름의 파일, 폴더 또는 링크가 있습니다. 다른 이름을 입력하세요."],
        "invalidTarget": ["目标须为 .command 文件夹，并含有同名普通脚本；不接受符号链接。", "目標須為 .command 資料夾，並含有同名一般指令稿；不接受符號連結。", ".command སྣོད་ནང་མིང་མཚུངས་པའི་ཡིག་ཆ་དགོས། མཚོན་རྟགས་སྦྲེལ་མཐུད་མི་ཆོག", "Select a .command folder containing a regular script with the same name. Symbolic links are not supported.", "同名の通常スクリプトを含む .command フォルダを選択してください。シンボリックリンクは使用できません。", "Choisissez un dossier .command contenant un script ordinaire du même nom, sans lien symbolique.", "Seleccione una carpeta .command con un script normal del mismo nombre. No se admiten enlaces simbólicos.", "Wählen Sie einen .command-Ordner mit einem gleichnamigen regulären Skript. Symbolische Links werden nicht unterstützt.", "Выберите папку .command с обычным скриптом того же имени. Символические ссылки не поддерживаются.", "같은 이름의 일반 스크립트가 있는 .command 폴더를 선택하세요. 심볼릭 링크는 지원하지 않습니다."],
        "writeFailed": ["无法写入快捷入口，请检查目录权限和剩余空间。", "無法寫入快捷入口，請檢查目錄權限和剩餘空間。", "འཕྲལ་འཇུག་འབྲི་མ་ཐུབ། ཆོག་མཆན་དང་སྟོང་ཆ་ཞིབ་བཤེར་བྱེད།", "Unable to write the launcher. Check folder permissions and free space.", "起動ファイルを書き込めません。フォルダの権限と空き容量を確認してください。", "Impossible d’écrire le lanceur. Vérifiez les permissions et l’espace disponible.", "No se pudo escribir el acceso. Compruebe los permisos y el espacio libre.", "Der Starter konnte nicht geschrieben werden. Prüfen Sie Berechtigungen und freien Speicher.", "Не удалось записать ярлык. Проверьте права на папку и свободное место.", "실행 파일을 쓸 수 없습니다. 폴더 권한과 여유 공간을 확인하세요."],
        "failureTitle": ["创建快捷入口未完成", "建立快捷入口未完成", "འཕྲལ་འཇུག་བཟོ་མ་ཐུབ།", "Launcher Not Created", "起動ファイルを作成できません", "Lanceur non créé", "Acceso no creado", "Starter nicht erstellt", "Ярлык не создан", "실행 파일 생성 실패"],
        "expired": ["右键请求已失效，请重新打开菜单。", "右鍵請求已失效，請重新開啟選單。", "རེ་ཞུ་དུས་ལས་ཡོལ། འདེམས་ཐོ་ཡང་བསྐྱར་ཁ་ཕྱེ།", "This request has expired. Reopen the context menu.", "この要求は無効です。右クリックメニューを開き直してください。", "Cette demande a expiré. Rouvrez le menu contextuel.", "La solicitud ha caducado. Abra de nuevo el menú contextual.", "Diese Anfrage ist abgelaufen. Öffnen Sie das Kontextmenü erneut.", "Запрос устарел. Откройте контекстное меню заново.", "요청이 만료되었습니다. 메뉴를 다시 여세요."],
        "hostMissing": ["缺少完整工具 App，请从管理面板安装 / 更新本功能。", "缺少完整工具 App，請從管理面板安裝 / 更新本功能。", "App ཆ་ཚང་མེད། དོ་དམ་ངོས་ནས་སྒྲིག་འཇུག་བྱེད།", "The tool app is missing. Install or update this feature in the manager.", "ツール App が見つかりません。管理画面からインストールまたは更新してください。", "L’app est introuvable. Installez ou mettez à jour cette fonction dans le gestionnaire.", "Falta la aplicación. Instale o actualice esta función desde el gestor.", "Die App fehlt. Installieren oder aktualisieren Sie die Funktion im Manager.", "Приложение отсутствует. Установите или обновите функцию через панель управления.", "도구 앱이 없습니다. 관리 패널에서 설치하거나 업데이트하세요."],
        "openFailed": ["无法启动快捷入口工具", "無法啟動快捷入口工具", "འཕྲལ་འཇུག་ལག་ཆ་འགོ་འཛུགས་མ་ཐུབ།", "Unable to open the launcher tool", "起動ファイル作成ツールを開けません", "Impossible d’ouvrir l’outil", "No se pudo abrir la herramienta", "Das Werkzeug konnte nicht geöffnet werden", "Не удалось запустить инструмент", "도구를 열 수 없습니다"],
        "system": ["跟随系统", "跟隨系統", "མ་ལག་རྗེས་འབྲང་།", "System", "システム", "Système", "Sistema", "System", "Системная", "시스템"],
        "light": ["白天", "白天", "ཉིན་མོ།", "Light", "ライト", "Clair", "Claro", "Hell", "Светлая", "라이트"],
        "dark": ["黑夜", "黑夜", "མཚན་མོ།", "Dark", "ダーク", "Sombre", "Oscuro", "Dunkel", "Тёмная", "다크"],
        "language": ["语言", "語言", "སྐད་ཡིག", "Language", "言語", "Langue", "Idioma", "Sprache", "Язык", "언어"],
        "theme": ["主题", "主題", "བརྗོད་གཞི།", "Theme", "テーマ", "Thème", "Tema", "Darstellung", "Тема", "테마"],
        "edit": ["编辑", "編輯", "རྩོམ་སྒྲིག", "Edit", "編集", "Édition", "Editar", "Bearbeiten", "Правка", "편집"],
        "cut": ["剪切", "剪下", "གཅོད།", "Cut", "切り取り", "Couper", "Cortar", "Ausschneiden", "Вырезать", "잘라내기"],
        "copy": ["复制", "複製", "འདྲ་བཤུས།", "Copy", "コピー", "Copier", "Copiar", "Kopieren", "Копировать", "복사"],
        "paste": ["粘贴", "貼上", "སྦྱར།", "Paste", "貼り付け", "Coller", "Pegar", "Einfügen", "Вставить", "붙여넣기"],
        "selectAll": ["全选", "全選", "ཚང་མ་འདེམས།", "Select All", "すべて選択", "Tout sélectionner", "Seleccionar todo", "Alles auswählen", "Выбрать всё", "모두 선택"],
        "quit": ["退出", "結束", "ཕྱིར་ཐོན།", "Quit", "終了", "Quitter", "Salir", "Beenden", "Выход", "종료"]
    ]

    static var language: String {
        let configured = defaults.string(forKey: "language") ?? "system"
        if languages.contains(configured) {
            return configured
        }
        let system = (UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String])?.first ?? Locale.preferredLanguages.first ?? "en"
        let normalized = system.lowercased().replacingOccurrences(of: "_", with: "-")
        if normalized.hasPrefix("zh") {
            return normalized.contains("hant") || normalized.contains("tw") || normalized.contains("hk") || normalized.contains("mo") ? "zh-Hant" : "zh-Hans"
        }
        return languages.first(where: { normalized.hasPrefix($0) }) ?? "en"
    }

    static func text(_ key: String) -> String {
        if key == "menu" {
            return "🔗 " + text("title")
        }
        let normalizedKey = key
        guard let values = translations[normalizedKey],
              let index = languages.firstIndex(of: language),
              values.indices.contains(index) else {
            return key
        }
        return values[index]
    }

    static func applyAppearance() {
        switch defaults.string(forKey: "theme") {
        case "dark":
            NSApp.byAppearance(NSAppearance.make(named: .darkAqua))
        case "light":
            NSApp.byAppearance(NSAppearance.make(named: .aqua))
        default:
            NSApp.byAppearance(nil)
        }
    }
}
