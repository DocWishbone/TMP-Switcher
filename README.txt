TEMP / TMP Umschalter
=====================

Start:
  Temp-Umschalter.cmd doppelklicken und die Administratorabfrage bestätigen.

Funktionen:
  - Zwei frei anpassbare Zielpfade (Vorgaben: C:\Windows\Temp und R:\Temp)
  - Systemweite Variablen TEMP und TMP auf einen der Zielpfade setzen
  - Die Zielpfade benutzerspezifisch unter %LOCALAPPDATA% speichern
  - Inhalt des aktuell aktiven TEMP-Ordners löschen
  - Geöffnete, gesperrte oder anderweitig nicht löschbare Einträge überspringen

Wichtig:
  Bereits laufende Programme behalten ihren alten TEMP-Pfad. Neue Prozesse
  übernehmen den neuen Wert. Vor einem problematischen Update empfiehlt sich
  nach dem Umschalten auf C:\Windows\Temp ein Windows-Neustart.

  Der Schalter betrifft die systemweiten (Machine-)Variablen. Persönliche
  TEMP/TMP-Werte des angemeldeten Benutzers werden nicht verändert.

Sicherheit:
  Laufwerkswurzeln wie C:\ koennen nicht als Ziel gespeichert werden. Die
  Aufraeumfunktion arbeitet ausschliesslich in einem der zwei konfigurierten
  Zielordner und loescht niemals den Zielordner selbst.
