//
//  PermanentDeleteLocalization.swift
//  JobsPermanentDeleter
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit

enum PermanentDeleteLocalization {

    static var defaults = UserDefaults(suiteName: "com.jobs.finderextensions.managementpanel.preferences")!
    static let languages = ["zh-Hans", "zh-Hant", "bo", "en", "ja", "fr", "es", "de", "ru", "ko"]
    static let languageNames = ["简体中文", "繁體中文", "བོད་ཡིག", "English", "日本語", "Français", "Español", "Deutsch", "Русский", "한국어"]
    static let translations: [String: [String]] = [
        "deleted": ["已永久删除","已永久刪除","རྩ་བ་ནས་སུབ་ཟིན།","Permanently deleted","完全に削除済み","Supprimés définitivement","Eliminados permanentemente","Endgültig gelöscht","Удалено навсегда","영구 삭제 완료"],
        "deleting": ["正在永久删除，请等待结果…","正在永久刪除，請等待結果…","རྩ་བ་ནས་སུབ་བཞིན་པ། སྒུག་རོགས།","Permanently deleting. Please wait for the result…","完全に削除しています。結果をお待ちください…","Suppression définitive en cours. Veuillez patienter…","Eliminando permanentemente. Espere el resultado…","Endgültiges Löschen läuft. Bitte warten…","Удаление без корзины. Дождитесь результата…","영구 삭제 중입니다. 결과를 기다려 주세요…"],
        "partial": ["本项可能已部分删除；未删除内容已保留。已删除内容无法由本工具恢复。","本項可能已部分刪除；未刪除內容已保留。已刪除內容無法由本工具還原。","ཆ་ཤས་སུབ་ཟིན་སྲིད། ལྷག་མ་ཉར་ཡོད། སུབ་ཟིན་པ་སླར་གསོ་མི་ཐུབ།","This item may be partially deleted. Remaining contents were retained; this tool cannot restore deleted contents.","一部削除済みの可能性があります。残りは保持され、削除済み内容はこのツールで復元できません。","Suppression partielle possible. Le contenu restant est conservé ; cet outil ne restaure pas le contenu supprimé.","Puede haberse eliminado una parte. Se conserva el resto; esta herramienta no puede restaurar lo eliminado.","Möglicherweise teilweise gelöscht. Restliche Inhalte bleiben erhalten; gelöschte Inhalte kann dieses Tool nicht wiederherstellen.","Объект мог быть удалён частично. Остаток сохранён; этот инструмент не восстанавливает удалённое.","일부가 삭제되었을 수 있습니다. 남은 내용은 보존되며 이 도구로 삭제된 내용을 복원할 수 없습니다."],
        "remaining": ["剩余内容位置","剩餘內容位置","ལྷག་མའི་གནས།","Remaining contents location","残りの内容の場所","Emplacement du contenu restant","Ubicación del contenido restante","Speicherort der verbliebenen Inhalte","Расположение оставшихся данных","남은 내용 위치"],
        "targets": ["删除目标","刪除目標","སུབ་ཡུལ།","Deletion targets","削除対象","Éléments à supprimer","Elementos a eliminar","Löschziele","Объекты удаления","삭제 대상"],
        "warning": ["确认永久删除以下项目？","確認永久刪除以下項目？","འདི་དག་རྩ་བ་ནས་སུབ་བམ།","Permanently delete these items?","以下の項目を完全に削除しますか？","Supprimer définitivement ces éléments ?","¿Eliminar estos elementos permanentemente?","Diese Objekte endgültig löschen?","Удалить эти объекты навсегда?","이 항목을 영구 삭제할까요?"],
        "confirm": ["确认","確認","གཏན་འཁེལ།","Confirm","確認","Confirmer","Confirmar","Bestätigen","Подтвердить","확인"],
        "menu": ["🗑️ 永久删除（不经过回收站）","🗑️ 永久刪除（不經過垃圾桶）","🗑️ གད་སྙིགས་སྒམ་མེད་པར་སུབ།","🗑️ Permanently delete (bypass Trash)","🗑️ 完全に削除（ゴミ箱を経由しない）","🗑️ Supprimer sans corbeille","🗑️ Eliminar sin papelera","🗑️ Endgültig löschen (ohne Papierkorb)","🗑️ Удалить без корзины","🗑️ 휴지통을 거치지 않고 영구 삭제"],
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
        "failureTitle": ["永久删除未完成","永久刪除未完成","རྩ་བ་ནས་སུབ་མ་ཐུབ།","Permanent deletion not completed","完全削除が未完了","Suppression définitive incomplète","Eliminación permanente incompleta","Endgültiges Löschen nicht abgeschlossen","Удаление не завершено","영구 삭제 미완료"],
        "title": ["永久删除所选项目","永久刪除所選項目","འདེམས་པ་རྩ་བ་ནས་སུབ།","Permanently delete selected items","選択項目を完全に削除","Supprimer définitivement la sélection","Eliminar permanentemente la selección","Auswahl endgültig löschen","Удалить выбранное навсегда","선택 항목 영구 삭제"],
        "scope": ["文件夹及其全部内容会直接删除，不能通过回收站恢复。符号链接只删除链接自身。左侧确认执行，右侧取消；回车、Esc 或关闭窗口均取消。","資料夾及全部內容會直接刪除，無法由垃圾桶還原。符號連結只刪除連結本身。左側確認，右側取消；Enter、Esc 或關窗均取消。","སྣོད་དང་ནང་གི་ཡིག་ཆ་ཚང་མ་སུབ། གད་སྙིགས་སྒམ་ནས་སླར་གསོ་མི་ཐུབ། སྦྲེལ་མཐུད་རང་ཉིད་ཁོ་ན་སུབ། གཡོན་གཏན་འཁེལ། གཡས་ཕྱིར་འཐེན། Enter / Esc དང་སྒོ་བརྒྱབ་ན་ཕྱིར་འཐེན།","Folders and all contents will be deleted directly and cannot be restored from Trash. Symbolic links delete only the link. Confirm is on the left, Cancel on the right. Return, Esc or closing cancels.","フォルダと全内容を直接削除し、ゴミ箱から復元できません。リンクはリンク自体のみ削除します。左で確認、右でキャンセル。Return・Esc・閉じるはキャンセルです。","Les dossiers et tout leur contenu seront supprimés sans restauration via la corbeille. Seul le lien symbolique est supprimé. Confirmer à gauche, annuler à droite. Entrée, Échap ou fermer annule.","Las carpetas y su contenido se eliminarán sin poder restaurarlos desde la papelera. Solo se borra el enlace simbólico. Confirmar a la izquierda y cancelar a la derecha. Intro, Esc o cerrar cancela.","Ordner mit sämtlichem Inhalt werden ohne Wiederherstellung aus dem Papierkorb gelöscht. Symbolische Links werden selbst gelöscht. Links bestätigen, rechts abbrechen. Eingabe, Esc oder Schließen bricht ab.","Папки со всем содержимым удаляются без восстановления из корзины. Символические ссылки удаляются без перехода по ним. Слева подтверждение, справа отмена. Enter, Esc и закрытие отменяют.","폴더와 모든 내용을 직접 삭제하며 휴지통에서 복원할 수 없습니다. 심볼릭 링크는 링크만 삭제합니다. 왼쪽 확인, 오른쪽 취소입니다. Enter, Esc 또는 창 닫기는 취소합니다."],
        "failed": ["未完成","未完成","མ་གྲུབ།","Not completed","未完了","Non terminé","Sin completar","Nicht abgeschlossen","Не завершено","완료하지 못함"],
        "invalidTarget": ["请求无效：请选择最多128个文件、文件夹或符号链接。不能选择系统关键目录、用户根目录、卷根目录或互相包含的目标；目标替换或无法访问时不会删除。","要求無效：最多128個檔案、資料夾或符號連結。不能選取系統重要目錄、使用者根目錄、卷根目錄或互相包含的目標；替換或無法存取時不刪除。","རེ་ཞུ་མི་འགྲིག ཡིག་ཆ་སྣོད་སྦྲེལ་མཐུད་128ལས་མང་མི་ཆོག མ་ལག་གི་རྩ་བ་དང་འགྱུར་ཟིན་ཡུལ་མི་སུབ།","Invalid request. Select up to 128 files, folders or symbolic links. System, home and volume roots or overlapping selections are blocked. Replaced or inaccessible targets are not deleted.","要求が無効です。ファイル・フォルダ・リンクは128個までです。システム・ホーム・ボリュームのルート、重複する階層、置換済みやアクセス不能な対象は削除しません。","Demande invalide. Jusqu’à 128 fichiers, dossiers ou liens. Racines système, personnelle ou de volume et sélections imbriquées bloquées. Aucune suppression des cibles remplacées ou inaccessibles.","Solicitud inválida. Hasta 128 archivos, carpetas o enlaces. Se bloquean raíces del sistema, usuario o volumen y selecciones anidadas. No se borran destinos reemplazados o inaccesibles.","Ungültige Anfrage. Bis zu 128 Dateien, Ordner oder Links. System-, Benutzer- und Volume-Wurzeln sowie verschachtelte Auswahl sind gesperrt. Ersetzte oder unzugängliche Ziele werden nicht gelöscht.","Некорректный запрос. До 128 файлов, папок или ссылок. Корни системы, пользователя, томов и вложенные выделения запрещены. Заменённые или недоступные цели не удаляются.","잘못된 요청입니다. 파일, 폴더, 링크를 최대 128개 선택하세요. 시스템·사용자·볼륨 루트 및 중첩 선택은 차단하며 교체되거나 접근할 수 없는 대상은 삭제하지 않습니다."],
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
