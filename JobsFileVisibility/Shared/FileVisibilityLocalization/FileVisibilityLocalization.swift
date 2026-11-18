//
//  FileVisibilityLocalization.swift
//  JobsFileVisibility
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit

enum FileVisibilityLocalization {

    static let defaults = UserDefaults(suiteName: "com.jobs.finderextensions.managementpanel.preferences")!
    static let languages = ["zh-Hans", "zh-Hant", "bo", "en", "ja", "fr", "es", "de", "ru", "ko"]
    static let languageNames = ["简体中文", "繁體中文", "བོད་ཡིག", "English", "日本語", "Français", "Español", "Deutsch", "Русский", "한국어"]
    static let translations: [String: [String]] = [
        "cancel": ["取消", "取消", "ཕྱིར་འཐེན།", "Cancel", "キャンセル", "Annuler", "Cancelar", "Abbrechen", "Отмена", "취소"],
        "ok": ["好", "好", "འགྲིག", "OK", "OK", "OK", "Aceptar", "OK", "ОК", "확인"],
        "expired": ["右键请求已失效，请重新打开菜单。", "右鍵請求已失效，請重新開啟選單。", "རེ་ཞུ་དུས་ལས་ཡོལ། འདེམས་ཐོ་ཡང་བསྐྱར་ཁ་ཕྱེ།", "This request has expired. Reopen the context menu.", "この要求は無効です。右クリックメニューを開き直してください。", "Cette demande a expiré. Rouvrez le menu contextuel.", "La solicitud ha caducado. Abra de nuevo el menú contextual.", "Diese Anfrage ist abgelaufen. Öffnen Sie das Kontextmenü erneut.", "Запрос устарел. Откройте контекстное меню заново.", "요청이 만료되었습니다. 메뉴를 다시 여세요."],
        "hostMissing": ["缺少完整工具 App，请从管理面板安装 / 更新本功能。", "缺少完整工具 App，請從管理面板安裝 / 更新本功能。", "App ཆ་ཚང་མེད། དོ་དམ་ངོས་ནས་སྒྲིག་འཇུག་བྱེད།", "The tool app is missing. Install or update this feature in the manager.", "ツール App が見つかりません。管理画面からインストールまたは更新してください。", "L’app est introuvable. Installez ou mettez à jour cette fonction dans le gestionnaire.", "Falta la aplicación. Instale o actualice esta función desde el gestor.", "Die App fehlt. Installieren oder aktualisieren Sie die Funktion im Manager.", "Приложение отсутствует. Установите или обновите функцию через панель управления.", "도구 앱이 없습니다. 관리 패널에서 설치하거나 업데이트하세요."],
        "system": ["跟随系统", "跟隨系統", "མ་ལག་རྗེས་འབྲང་།", "System", "システム", "Système", "Sistema", "System", "Системная", "시스템"],
        "light": ["白天", "白天", "ཉིན་མོ།", "Light", "ライト", "Clair", "Claro", "Hell", "Светлая", "라이트"],
        "dark": ["黑夜", "黑夜", "མཚན་མོ།", "Dark", "ダーク", "Sombre", "Oscuro", "Dunkel", "Тёмная", "다크"],
        "language": ["语言", "語言", "སྐད་ཡིག", "Language", "言語", "Langue", "Idioma", "Sprache", "Язык", "언어"],
        "theme": ["主题", "主題", "བརྗོད་གཞི།", "Theme", "テーマ", "Thème", "Tema", "Darstellung", "Тема", "테마"],
        "quit": ["退出", "結束", "ཕྱིར་ཐོན།", "Quit", "終了", "Quitter", "Salir", "Beenden", "Выход", "종료"],
        "failureTitle": ["隐藏属性操作未完成", "隱藏屬性操作未完成", "སྦས་རྟགས་བསྒྱུར་མ་ཐུབ།", "Visibility Change Not Completed", "非表示属性を変更できません", "Visibilité non modifiée", "Cambio de visibilidad incompleto", "Sichtbarkeit nicht geändert", "Изменение видимости не завершено", "숨김 속성 변경 실패"],
        "title": ["所选项目隐藏属性","所選項目隱藏屬性","འདེམས་པའི་ཡིག་ཆའི་སྦས་པའི་ཁྱད་ཆོས།","Selected Item Visibility","選択項目の非表示属性","Visibilité des éléments sélectionnés","Visibilidad de elementos seleccionados","Sichtbarkeit ausgewählter Objekte","Видимость выбранных объектов","선택 항목 숨김 속성"],
        "hide": ["🙈 隐藏所选项目","🙈 隱藏所選項目","🙈 འདེམས་པ་སྦེད།","🙈 Hide selected items","🙈 選択項目を非表示","🙈 Masquer la sélection","🙈 Ocultar selección","🙈 Auswahl ausblenden","🙈 Скрыть выбранное","🙈 선택 항목 숨기기"],
        "show": ["👁️ 显示所选项目","👁️ 顯示所選項目","👁️ འདེམས་པ་སྟོན།","👁️ Unhide selected items","👁️ 選択項目の非表示を解除","👁️ Réafficher la sélection","👁️ Mostrar selección","👁️ Auswahl einblenden","👁️ Показать выбранное","👁️ 선택 항목 숨김 해제"],
        "apply": ["应用","套用","ཉེར་སྤྱོད།","Apply","適用","Appliquer","Aplicar","Anwenden","Применить","적용"],
        "scope": ["仅修改以下文件／文件夹自身的隐藏属性；不递归、不改名、不更改 Finder 全局偏好。显示操作清除隐藏属性，点开头名称及其它 Finder 规则仍可能使其隐藏。","僅修改以下檔案／資料夾自身的隱藏屬性；不遞迴、不改名、不變更 Finder 全域偏好。顯示操作清除隱藏屬性，點開頭名稱及其他 Finder 規則仍可能使其隱藏。","འདེམས་པའི་ཡིག་ཆ་དང་སྣོད་ཀྱི་སྦས་རྟགས་ཁོ་ན་བསྒྱུར། ནང་ཚུད་དང་མིང་དང་ Finder སྒྲིག་འགོད་མི་བསྒྱུར། ཚེག་གིས་འགོ་བཙུགས་པའི་མིང་སྦས་པར་གནས་སྲིད།","Change only the hidden flag of these files or folders. No recursion, renaming or global Finder preference changes. Clearing the flag does not override dot names or other Finder rules.","選択したファイル／フォルダ自身の非表示属性のみを変更します。再帰処理、改名、Finder 全体設定の変更は行いません。ドット名や他の規則による非表示は残ります。","Modifie uniquement l’attribut masqué des éléments choisis. Aucun parcours récursif, renommage ni réglage global du Finder. Les noms à point et autres règles peuvent les laisser masqués.","Cambia solo el atributo oculto de los archivos o carpetas elegidos. Sin recursión, cambio de nombre ni ajustes globales de Finder. Los nombres con punto y otras reglas pueden mantenerlos ocultos.","Ändert nur das Versteckt-Attribut dieser Dateien oder Ordner. Keine Rekursion, Umbenennung oder globalen Finder-Einstellungen. Punktnamen und andere Regeln können weiterhin verbergen.","Меняется только флаг скрытия самих файлов или папок. Без рекурсии, переименования и глобальных настроек Finder. Имена с точкой и другие правила могут сохранять скрытие.","선택한 파일/폴더 자체의 숨김 속성만 변경합니다. 하위 항목, 이름, Finder 전역 설정은 변경하지 않습니다. 점으로 시작하는 이름이나 다른 Finder 규칙으로 계속 숨겨질 수 있습니다."],
        "hiddenResult": ["已设置隐藏属性","已設定隱藏屬性","སྦས་རྟགས་བཀོད་ཟིན།","Hidden flag set","非表示属性を設定済み","Attribut masqué activé","Atributo oculto activado","Versteckt-Attribut gesetzt","Флаг скрытия установлен","숨김 속성 설정 완료"],
        "shownResult": ["已清除隐藏属性","已清除隱藏屬性","སྦས་རྟགས་བསལ་ཟིན།","Hidden flag cleared","非表示属性を解除済み","Attribut masqué retiré","Atributo oculto eliminado","Versteckt-Attribut entfernt","Флаг скрытия снят","숨김 속성 해제 완료"],
        "failed": ["未完成","未完成","མ་གྲུབ།","Not completed","未完了","Non terminé","Sin completar","Nicht abgeschlossen","Не завершено","완료하지 못함"],
        "invalidTarget": ["请求无效：请选择普通文件／文件夹（不含符号链接），最多128项；目标已替换或无法访问时不会处理。","請求無效：請選擇一般檔案／資料夾（不含符號連結），最多128項；目標已替換或無法存取時不會處理。","རེ་ཞུ་མི་འགྲིག ཡིག་ཆ་དང་སྣོད་128ལས་མང་མི་ཆོག སྦྲེལ་མཐུད་མི་ཆོག","Invalid request. Select up to 128 regular files or folders, excluding symbolic links. Replaced or inaccessible targets are not processed.","通常のファイル／フォルダを128個まで選択してください。シンボリックリンク、置換済みやアクセス不能な対象は処理しません。","Demande invalide. Sélectionnez au plus 128 fichiers ou dossiers ordinaires, sans liens symboliques. Les cibles remplacées ou inaccessibles ne sont pas traitées.","Solicitud inválida. Seleccione hasta 128 archivos o carpetas normales, sin enlaces simbólicos. No se procesan destinos reemplazados o inaccesibles.","Ungültige Anfrage. Bis zu 128 reguläre Dateien oder Ordner wählen, keine symbolischen Links. Ersetzte oder nicht erreichbare Ziele bleiben unverändert.","Некорректный запрос. Выберите до 128 обычных файлов или папок без символических ссылок. Заменённые и недоступные объекты не обрабатываются.","잘못된 요청입니다. 심볼릭 링크를 제외한 일반 파일/폴더를 최대 128개 선택하세요. 교체되었거나 접근할 수 없는 대상은 처리하지 않습니다."],
        "dotName": ["部分名称以点开头；隐藏属性已清除，但 Finder 仍可能按名称或其它规则隐藏它们。未自动改名。","部分名稱以點開頭；隱藏屬性已清除，但 Finder 仍可能依名稱或其他規則隱藏它們。未自動改名。","མིང་ཁ་ཤས་ཚེག་གིས་འགོ་བཙུགས། སྦས་རྟགས་བསལ་ཡང་ Finder ནང་སྦས་པར་གནས་སྲིད། མིང་མ་བསྒྱུར།","Some names begin with a dot. Their hidden flag was cleared, but Finder may still hide them by name or other rules. No names were changed.","ドットで始まる名前は属性解除後も Finder の規則で非表示になる場合があります。名前は変更していません。","Certains noms commencent par un point. Le drapeau a été retiré, mais le Finder peut encore les masquer. Aucun nom modifié.","Algunos nombres empiezan por punto. Se eliminó el atributo, pero Finder aún puede ocultarlos. No se cambió ningún nombre.","Einige Namen beginnen mit einem Punkt. Das Attribut wurde entfernt, Finder kann sie weiterhin verbergen. Keine Namen geändert.","Некоторые имена начинаются с точки. Флаг снят, но Finder может по-прежнему скрывать их. Имена не менялись.","일부 이름이 점으로 시작합니다. 숨김 속성을 해제해도 Finder 규칙으로 계속 숨겨질 수 있습니다. 이름은 변경하지 않았습니다."],
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
