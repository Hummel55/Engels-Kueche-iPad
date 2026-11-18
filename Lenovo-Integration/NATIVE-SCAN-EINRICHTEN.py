# -*- coding: utf-8 -*-
"""Minimaler Patch fuer das bestehende Kuechentool. Loescht keine Rezeptdaten."""
from pathlib import Path
from datetime import datetime
import argparse
import shutil
import sys

BRIDGE = r'''
// Engels Kueche Native iPad App: Foto nur fuer OCR als Entwurf benutzen.
// Aufnahmen werden nicht als Original-Rezeptfoto dauerhaft gespeichert.
window.kitchenNativeScanPhoto=function(photoData){
  if(typeof photoData!=='string'||photoData.indexOf('data:image/jpeg;base64,')!==0){
    alert('Kamera hat kein gueltiges JPEG geliefert.');return;
  }
  localEditor({},photoData);
  var current=editing;
  if(!current||!current.inputs){alert('Rezepteditor konnte nicht geoeffnet werden.');return;}
  // Nur im Arbeitsspeicher des Webbrowsers; NICHT als Rezeptbild persistieren.
  current.photo=null;
  current.ocrPhoto=photoData;
  current.inputs.mode.value='auto';
  current.inputs.status.textContent='Foto aus der iPad-Frontkamera wird erkannt ...';
  recognizePhoto(current,{photo_data:photoData});
};
'''
ANCHOR = 'window.kitchenManualRecipe=function(data){localEditor({},data&&data.photo_data)};'


def main():
    p=argparse.ArgumentParser(description='Native Scan-Schnittstelle fuer Engels Kueche ergaenzen')
    p.add_argument('--kueche', help='Pfad zum Kuechenordner (enthaelt web\\recipes.js)')
    args=p.parse_args()
    folders = [Path(args.kueche)] if args.kueche else [Path(r'C:\Kueche'),Path(r'C:\Küche'),Path(r'C:\Engels Küche')]
    dest=None
    for folder in folders:
        path=folder/'web'/'recipes.js'
        if path.is_file():dest=path;break
    if dest is None:
        print('Kuechenordner nicht gefunden. Beispiel:')
        print(r'python NATIVE-SCAN-EINRICHTEN.py --kueche "C:\Küche"')
        sys.exit(2)
    content=dest.read_text(encoding='utf-8-sig')
    if 'window.kitchenNativeScanPhoto=function' in content:
        print('Die Schnittstelle ist bereits vorhanden. Keine Aenderung.');return
    if ANCHOR not in content:
        print('Keine Aenderung: Unerwartete recipes.js-Version. Bitte Datei pruefen lassen.')
        sys.exit(3)
    stamp=datetime.now().strftime('%Y%m%d-%H%M%S')
    backup=dest.with_name('recipes.js.vor-native-'+stamp+'.bak')
    shutil.copy2(dest,backup)
    amended=content.replace(ANCHOR,BRIDGE+'\n'+ANCHOR,1)
    temp=dest.with_suffix('.js.native-tmp')
    temp.write_text(amended,encoding='utf-8')
    temp.replace(dest)
    print('Native Scan-Schnittstelle eingerichtet:',dest)
    print('Sicherung:',backup)
    print('REZEPTDATENBANK UND FOTOS WURDEN NICHT VERAENDERT.')

if __name__=='__main__':main()
