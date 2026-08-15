#!/usr/bin/env python3
"""Append the undo keys to all eight .strings files, in one place so the eight
cannot drift apart while they are being written."""
import io, os

KEYS = [
    ("Put back", {
        "en": "Put back", "ru": "Вернуть", "es": "Devolver", "fr": "Restaurer",
        "de": "Zurücklegen", "ja": "元に戻す", "zh": "放回", "pt": "Devolver"}),
    ("back where it was", {
        "en": "back where it was", "ru": "возвращено", "es": "devuelto a su sitio",
        "fr": "remis en place", "de": "zurückgelegt", "ja": "元の場所に戻り済み",
        "zh": "已放回原处", "pt": "devolvido ao lugar"}),
    ("The mark that stops a rule acting twice could not be written, so the rule may take this file again within the hour.", {
        "en": "The mark that stops a rule acting twice could not be written, so the rule may take this file again within the hour.",
        "ru": "Метку, которая не даёт правилу сработать дважды, записать не удалось — в течение часа правило может забрать этот файл снова.",
        "es": "No se pudo escribir la marca que impide que una regla actúe dos veces, así que la regla puede llevarse este archivo otra vez en la próxima hora.",
        "fr": "La marque qui empêche une règle d’agir deux fois n’a pas pu être écrite\u{00a0}: la règle peut reprendre ce fichier dans l’heure.",
        "de": "Die Markierung, die eine Regel am zweiten Zugriff hindert, ließ sich nicht schreiben – die Regel kann diese Datei innerhalb einer Stunde erneut nehmen.",
        "ja": "ルールが二度目に働くのを止める印を書き込めませんでした。1 時間以内にルールがこのファイルを再び動かす可能性があります。",
        "zh": "无法写入阻止规则重复执行的标记，规则可能在一小时内再次处理这个文件。",
        "pt": "Não foi possível gravar a marca que impede uma regra de agir duas vezes, então a regra pode levar este arquivo de novo dentro de uma hora."}),
    ("The record of what Autopilot did was not written by Helm, so nothing in it can be put back.", {
        "en": "The record of what Autopilot did was not written by Helm, so nothing in it can be put back.",
        "ru": "Записи о том, что делал автопилот, написаны не Helm — вернуть из них ничего нельзя.",
        "es": "El registro de lo que hizo el piloto automático no lo escribió Helm, así que no se puede devolver nada de él.",
        "fr": "Le relevé de ce qu’a fait le pilote automatique n’a pas été écrit par Helm\u{00a0}: rien ne peut en être restauré.",
        "de": "Das Protokoll dessen, was der Autopilot getan hat, stammt nicht von Helm – daraus lässt sich nichts zurücklegen.",
        "ja": "オートパイロットの記録は Helm が書いたものではありません。そこから元に戻せるものはありません。",
        "zh": "自动驾驶的操作记录不是 Helm 写的，因此其中的任何内容都无法放回。",
        "pt": "O registro do que o piloto automático fez não foi escrito pelo Helm, então nada nele pode ser devolvido."}),
    ("Clear the record and start again", {
        "en": "Clear the record and start again", "ru": "Очистить историю и начать заново",
        "es": "Borrar el registro y empezar de nuevo",
        "fr": "Effacer le relevé et recommencer",
        "de": "Protokoll löschen und neu beginnen",
        "ja": "記録を消して最初から", "zh": "清除记录并重新开始",
        "pt": "Limpar o registro e começar de novo"}),
    ("it is no longer where Autopilot put it", {
        "en": "it is no longer where Autopilot put it",
        "ru": "его больше нет там, куда его положил автопилот",
        "es": "ya no está donde lo puso el piloto automático",
        "fr": "il n’est plus là où le pilote automatique l’avait mis",
        "de": "sie liegt nicht mehr dort, wo der Autopilot sie abgelegt hat",
        "ja": "オートパイロットが置いた場所にもうありません",
        "zh": "它已不在自动驾驶放置的位置",
        "pt": "não está mais onde o piloto automático o colocou"}),
    ("something else is there now", {
        "en": "something else is there now", "ru": "там теперь другой файл",
        "es": "ahora hay otra cosa ahí", "fr": "autre chose s’y trouve désormais",
        "de": "dort liegt jetzt etwas anderes", "ja": "そこには別のものがあります",
        "zh": "那里现在是别的文件", "pt": "agora há outra coisa ali"}),
    ("the folder it came from is gone", {
        "en": "the folder it came from is gone", "ru": "папки, откуда он взят, больше нет",
        "es": "la carpeta de la que venía ya no existe",
        "fr": "le dossier d’origine n’existe plus",
        "de": "der Ordner, aus dem sie kam, ist weg",
        "ja": "元のフォルダがなくなっています", "zh": "它原来所在的文件夹已不存在",
        "pt": "a pasta de onde veio não existe mais"}),
    ("it is outside the folders a rule may reach", {
        "en": "it is outside the folders a rule may reach",
        "ru": "он вне папок, куда правилу можно",
        "es": "está fuera de las carpetas a las que una regla puede llegar",
        "fr": "il est hors des dossiers auxquels une règle peut accéder",
        "de": "sie liegt außerhalb der Ordner, die eine Regel erreichen darf",
        "ja": "ルールが触れてよいフォルダの外にあります",
        "zh": "它不在规则可以触及的文件夹内",
        "pt": "está fora das pastas que uma regra pode alcançar"}),
    ("the old name is taken", {
        "en": "the old name is taken", "ru": "старое имя занято",
        "es": "el nombre anterior está ocupado", "fr": "l’ancien nom est déjà pris",
        "de": "der alte Name ist belegt", "ja": "元の名前はすでに使われています",
        "zh": "原来的名称已被占用", "pt": "o nome antigo está ocupado"}),
    ("it is no longer in the Trash", {
        "en": "it is no longer in the Trash", "ru": "его больше нет в Корзине",
        "es": "ya no está en la papelera", "fr": "il n’est plus dans la corbeille",
        "de": "sie ist nicht mehr im Papierkorb", "ja": "ゴミ箱にもうありません",
        "zh": "它已不在废纸篓中", "pt": "não está mais no Lixo"}),
    ("it has already been put back", {
        "en": "it has already been put back", "ru": "он уже возвращён",
        "es": "ya se devolvió", "fr": "il a déjà été restauré",
        "de": "sie wurde bereits zurückgelegt", "ja": "すでに元に戻されています",
        "zh": "它已经被放回", "pt": "já foi devolvido"}),
    ("this record was not written by Helm", {
        "en": "this record was not written by Helm", "ru": "эта запись написана не Helm",
        "es": "este registro no lo escribió Helm",
        "fr": "cette entrée n’a pas été écrite par Helm",
        "de": "dieser Eintrag stammt nicht von Helm",
        "ja": "この記録は Helm が書いたものではありません",
        "zh": "这条记录不是 Helm 写的", "pt": "este registro não foi escrito pelo Helm"}),
    ("Helm did not record enough to put it back", {
        "en": "Helm did not record enough to put it back",
        "ru": "Helm записал слишком мало, чтобы вернуть его",
        "es": "Helm no registró lo suficiente para devolverlo",
        "fr": "Helm n’en a pas assez noté pour le restaurer",
        "de": "Helm hat zu wenig festgehalten, um sie zurückzulegen",
        "ja": "元に戻すのに足りる記録が Helm にありません",
        "zh": "Helm 记录的信息不足以将其放回",
        "pt": "o Helm não registrou o suficiente para devolvê-lo"}),
]

ROOT = "Sources/HelmUI/Resources"
for lang in ["en", "ru", "es", "fr", "de", "ja", "zh", "pt"]:
    path = os.path.join(ROOT, f"{lang}.lproj/Localizable.strings")
    with io.open(path, "r", encoding="utf-8") as f:
        text = f.read()
    if not text.endswith("\n"):
        text += "\n"
    for key, table in KEYS:
        assert f'"{key}" =' not in text, f"{lang}: {key} already there"
        text += f'"{key}" = "{table[lang]}";\n'
    with io.open(path, "w", encoding="utf-8") as f:
        f.write(text)
print("appended", len(KEYS), "keys to eight files")
